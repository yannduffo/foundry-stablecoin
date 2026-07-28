//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./librairies/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Yann Duffo
 *
 * The system is design to be minimal, and maintain 1DSC == 1USD
 * StableCoin properties : collateral -> exogenous (ETH & BTC), minting -> Algorithmic, stability -> pegged to USD
 *
 * It is similar to DAI w/ no governance, no fees and only backed w/ WETH & WBTC
 * DSC system should always be overcollateralized (never should value(collateral) < value(all DSC))
 *
 * @notice : This contract is the core of DSC system. It handle all the logic for mining and redeeming DSC as well as depositing & withdrawing collateral.
 * @notice : based on MakerDAO (DAI) system.
 *
 */
contract DSCEngine is ReentrancyGuard {
    // ---------------------------------- Errors -----------------------------------
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSGEngine__InvalidPrice();
    error DSCEngine__HealthFactorIsOK();
    error DSCEngine__HeathFactorNotImproved();

    // ---------------------------------- Types ------------------------------------
    using OracleLib for AggregatorV3Interface;

    // ----------------------------- State variables -------------------------------
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized -> (to get 100DSC : 200$ of ETH * 50% = 100 // 100/100 = healthFactor limit)
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_DSC;

    // ---------------------------------- Events -----------------------------------
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    // --------------------------------- Modifiers ---------------------------------
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert DSCEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        //checking if it exists on the allowed token mapping
        if (s_priceFeeds[token] == address(0)) revert DSCEngine__NotAllowedToken();
        _;
    }

    // --------------------------------- Functions ---------------------------------
    // ------------------------------ External Func --------------------------------
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address DSCAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i]; //filling our local mapping
            s_collateralTokens.push(tokenAddresses[i]); //filling our collateral token table
        }
        i_DSC = DecentralizedStableCoin(DSCAddress);
    }

    /**
     * @param tokenCollateralAddress Address of token to deposit
     * @param amountCollateral Amount of collateral to deposit
     * @param amountDscToMint Amount of stablecoin to mint
     * @notice This fonction will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @notice follows CEI (Checks, Effects, Interactions)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }

    /**
     * @param tokenCollateralAddress Address of the collateral token
     * @param amountCollateral Amount of the collateral to redeem
     * @param amountDSCToBurn Amount of DSC to burn
     * This function burns DSC and redeems underlying collateral in one transaction
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)
        external
    {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeemCollateral already checks healtFactor
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        //revert if healthFactor(msg.sender) < 1
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param amountDSCToMint The amount of DSC to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        //actual mint :
        bool minted = i_DSC.mint(msg.sender, amountDSCToMint);
        if (!minted) revert DSCEngine__MintFailed();
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //we will see if it's usefull
    }

    /**
     * @param collateral The ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. healthFactor should be under MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC to burn to improve user healthFactor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized
     * @notice Indeed, if the protocol were 100% or less collateralized, we wouldn't be able to incentive the liquidators
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        //checks
        uint256 startingHealfFactor = _healthFactor(user);
        if (startingHealfFactor >= MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorIsOK();

        //effects & interactions (burn DSC debt, transfer collateral + 10% bonus to liquidator)
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered) * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        // redeem and burn :
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDSC(debtToCover, user, msg.sender);

        //cheking healthFactor (after interactions)
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingHealfFactor) {
            revert DSCEngine__HeathFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender); //also checking liquidator HF
    }

    function getHealthFactor() external view {}

    // --------------------- Private & Internal View Func ---------------------------
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }

    /**
     * @dev Low level func, do not call w/o cheking healthFactor
     */
    function _burnDSC(uint256 amountDSCToBurn, address onBehalfOf, address DSCFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDSCToBurn;
        bool success = i_DSC.transferFrom(DSCFrom, address(this), amountDSCToBurn);
        if (!success) revert DSCEngine__TransferFailed();
        i_DSC.burn(amountDSCToBurn);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
        return (totalDSCMinted, collateralValueInUSD); //return isn't necessary here (solidity syntaxe returns by default)
    }

    /**
     * @return How close to liquidation a user is (below 1 -> they can get liquidated)
     * @param user The user interrogated
     * @notice The comparaison should be "value compared"
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd) * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION; // = 50% of collateralValueInUSD
        return collateralAdjustedForThreshold * PRECISION / totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert DSCEngine__BreakHealthFactor(userHealthFactor);
    }

    // ---------------------- Public & External View Func ---------------------------
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        // return ($e18 * 1e18) / ($e8 * 1e10)
        return (usdAmountInWei * PRECISION) / (SafeCast.toUint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @notice Loop through collateral mapping and sum all entries $ value
     * @param user The user adddres which we calculate collateral value
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            //get token amount
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];

            //convert to USD and sum
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        //getting last price
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData(); //price is return in 1000 * 1e8

        if (price <= 0) revert DSGEngine__InvalidPrice();

        uint256 unsignedPrice = SafeCast.toUint256(price);

        //converting (closely looking at the decimals) and returning
        return (unsignedPrice * ADDITIONAL_FEED_PRECISION * amount) / PRECISION; // (1e18 * 1e18) / 1e18 to stay in wei
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        (totalDSCMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }
}
