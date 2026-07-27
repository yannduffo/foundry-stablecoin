//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

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

    // ----------------------------- State variables -------------------------------
    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

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
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address DSCAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i]; //filling up our local mapping
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
        if(!success) revert DSCEngine__TransferFailed();
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function mintDSC() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
