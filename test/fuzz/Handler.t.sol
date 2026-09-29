//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice The handler narrows down the fuzzer random calls so that every call made to
 *          DSCEngine is a valid one
 */
contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    address[] public usersWithCollateralDeposited;
    mapping(address user => bool) private hasDeposited; //avoids pushing the same user twice

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        if (!hasDeposited[msg.sender]) {
            hasDeposited[msg.sender] = true;
            usersWithCollateralDeposited.push(msg.sender);
        }
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDSCToMint = (SafeCast.toInt256(collateralValueInUsd) / 2) - SafeCast.toInt256(totalDSCMinted);
        if (maxDSCToMint < 0) return;
        amount = bound(amount, 0, SafeCast.toUint256(maxDSCToMint));
        if (amount == 0) return;

        vm.startPrank(sender);
        dsce.mintDSC(amount);
        vm.stopPrank();
    }

    function burnDSC(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        //a user can only burn the DSC they hold
        amount = bound(amount, 0, dsc.balanceOf(sender));
        if (amount == 0) return;

        vm.startPrank(sender);
        dsc.approve(address(dsce), amount);
        dsce.burnDSC(amount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        //a user can't redeem more than they deposited
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(sender, address(collateral));

        //and must keep at least 2x their debt in collateral value (200% overcollateralized)
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        uint256 requiredCollateralValueInUsd = totalDSCMinted * 2;
        if (collateralValueInUsd <= requiredCollateralValueInUsd) return;
        uint256 excessValueInUsd = collateralValueInUsd - requiredCollateralValueInUsd;
        uint256 maxRedeemableFromExcess = dsce.getTokenAmountFromUsd(address(collateral), excessValueInUsd);
        if (maxRedeemableFromExcess < maxCollateralToRedeem) maxCollateralToRedeem = maxRedeemableFromExcess;

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) return;

        vm.prank(sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function getUserWithCollateralDeposited() external view returns (address[] memory) {
        return usersWithCollateralDeposited;
    }

    // ----------------------------------
    //----------------- Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
