//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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

    // ----------------------------- State variables -------------------------------
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized -> (to get 100DSC : 200$ of ETH * 50% = 100 // 100/100 = healthFactor limit)
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_DSC;

    // ---------------------------------- Events -----------------------------------
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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

    function depositCollateralAndMintDSC() external {}

    /**
     * @notice follows CEI (Checks, Effects, Interactions)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    /**
     * @param amountDSCToMint The amount of DSC to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDSC(uint256 amountDSCToMint) external moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        //actual mint :
        bool minted = i_DSC.mint(msg.sender, amountDSCToMint);
        if(!minted) revert DSCEngine__MintFailed();
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    // --------------------- Private & Internal View Func ---------------------------
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
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD) * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION; // = 50% of collateralValueInUSD
        return collateralAdjustedForThreshold * PRECISION / totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert DSCEngine__BreakHealthFactor(userHealthFactor);
    }

    // ---------------------- Public & External View Func ---------------------------
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
        (, int256 price,,,) = priceFeed.latestRoundData(); //price is return in 1000 * 1e8

        if(price <= 0) revert DSGEngine__InvalidPrice();

        uint256 unsignedPrice = SafeCast.toUint256(price);

        //converting (closely looking at the decimals) and returning
        return (unsignedPrice * ADDITIONAL_FEED_PRECISION * amount) / PRECISION; // (1e18 * 1e18) / 1e18 to stay in wei
    }
}
