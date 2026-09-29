//SPDX-License-Identifier : MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant STRATING_ERC20_BALANCE = 10 ether;
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    function setUp() public {
        //deploy the infrastructure
        deployer = new DeployDSC();
        (dsc, dscEngine, weth, wbtc) = deployer.run();

        //getting feeds addresses
        ethUsdPriceFeed = dscEngine.getCollateralTokenPriceFeed(weth);
        btcUsdPriceFeed = dscEngine.getCollateralTokenPriceFeed(wbtc);

        //minting some token to get ready
        ERC20Mock(weth).mint(user, STRATING_ERC20_BALANCE);
    }

    // -------------------------- Constructor tests --------------------------
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    // -------------------------- Price tests --------------------------
    //right now only working for Anvil deployment
    function testGetUsdValue() public view {
        //the test : 15ETH * 2000$/ETH = $30000e18
        uint256 ethAmount = 15 ether;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUSDValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    // ----------------- deposit & collaterol tests --------------------
    function testRevertIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);

        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        ERC20Mock(randomToken).mint(user, STRATING_ERC20_BALANCE);

        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(randomToken), 1 ether);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);
        uint256 expectedTotalDSCMinted = 0;
        uint256 expectedCollateralValueIUsd = dscEngine.getAccountCollateralValue(user);
        assertEq(totalDSCMinted, expectedTotalDSCMinted);
        assertEq(collateralValueInUsd, expectedCollateralValueIUsd);
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    // ------------------------ deposit collateral and mint tests ------------------
    function testRevertsIfMintedDSCBreakHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 priceUint256 = SafeCast.toUint256(price);

        uint256 amountToMint =
            (AMOUNT_COLLATERAL * (priceUint256 * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL));

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    // ----------------------- brun tests ----------------------
    function testRevertIfBurnAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDSC(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert();
        dscEngine.burnDSC(1);
    }

    modifier depositCollateralAndMintDSC() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanBurnDsc() public depositCollateralAndMintDSC {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.burnDSC(AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    // ---------------------------- deposit event test -----------------------------
    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, false, address(dscEngine));
        emit DSCEngine.CollateralDeposited(user, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        assertEq(dscEngine.getCollateralBalanceOfUser(user, weth), AMOUNT_COLLATERAL);
    }

    // -------------------------------- mint tests ---------------------------------
    function testRevertIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDSC(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.mintDSC(AMOUNT_TO_MINT);
        vm.stopPrank();

        (uint256 totalDSCMinted,) = dscEngine.getAccountInformation(user);
        assertEq(totalDSCMinted, AMOUNT_TO_MINT);
        assertEq(dsc.balanceOf(user), AMOUNT_TO_MINT);
    }

    // ------------------------ depositCollateralAndMint tests ---------------------
    function testCanDepositCollateralAndMint() public depositCollateralAndMintDSC {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);

        assertEq(dsc.balanceOf(user), AMOUNT_TO_MINT);
        assertEq(totalDSCMinted, AMOUNT_TO_MINT);
        assertEq(collateralValueInUsd, dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL));
    }

    // ---------------------------- redeemCollateral tests -------------------------
    function testRevertIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        // collateral is back in the user's wallet and the engine holds nothing
        assertEq(ERC20Mock(weth).balanceOf(user), STRATING_ERC20_BALANCE);
        assertEq(dscEngine.getCollateralBalanceOfUser(user, weth), 0);
    }

    function testRedeemRevertsIfHealthFactorBroken() public depositCollateralAndMintDSC {
        // user has DSC minted, redeeming all collateral would break the health factor
        vm.startPrank(user);
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // ------------------------------ healthFactor tests ---------------------------
    function testProperlyReportsHealthFactor() public depositCollateralAndMintDSC {
        // 10 ETH * $2000 = $20000 collateral, 100 DSC minted
        // ($20000 * 50 / 100) * 1e18 / 100 = 100e18
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dscEngine.calculateHealthFactor(AMOUNT_TO_MINT, dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL));
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositCollateralAndMintDSC {
        // ETH price tanks from $2000 to $18 -> collateral now worth $180
        // ($180 * 50 / 100) * 1e18 / 100 = 0.9e18 < MIN_HEALTH_FACTOR
        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);
        uint256 healthFactor = dscEngine.calculateHealthFactor(totalDSCMinted, collateralValueInUsd);
        assertLt(healthFactor, 1 ether);
    }

    // ------------------------------ liquidation tests ----------------------------
    modifier liquidated() {
        // user takes on debt at $2000/ETH
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        // price crashes so the user's health factor breaks
        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // liquidator deposits, mints and covers the whole debt
        ERC20Mock(weth).mint(liquidator, COLLATERAL_TO_COVER);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_TO_COVER);
        dscEngine.depositCollateralAndMintDSC(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.liquidate(weth, user, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testLiquidationRevertsIfHealthFactorOk() public depositCollateralAndMintDSC {
        // user is healthy, cannot be liquidated
        ERC20Mock(weth).mint(liquidator, COLLATERAL_TO_COVER);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_TO_COVER);
        dscEngine.depositCollateralAndMintDSC(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOK.selector);
        dscEngine.liquidate(weth, user, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testLiquidationClearsUserDebt() public liquidated {
        (uint256 userDscMinted,) = dscEngine.getAccountInformation(user);
        assertEq(userDscMinted, 0);
    }

    function testLiquidatorReceivesCollateralPlusBonus() public liquidated {
        // debt = 100 DSC, price = $18 -> 100/18 = 5.555... ETH covered
        // + 10% bonus = 6.111... ETH transferred to the liquidator
        uint256 expectedCovered = dscEngine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT);
        uint256 expectedWeth = expectedCovered + (expectedCovered * 10 / 100);
        assertEq(ERC20Mock(weth).balanceOf(liquidator), expectedWeth);
    }

    // -------------------------------- getter tests -------------------------------
    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetCollateralTokenPriceFeed() public view {
        assertEq(dscEngine.getCollateralTokenPriceFeed(weth), ethUsdPriceFeed);
    }

    function testGetPrecision() public view {
        assertEq(dscEngine.getPrecision(), 1e18);
    }
}
