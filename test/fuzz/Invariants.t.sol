//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

/// What should be our invariants ?
/// -> The total value of collateral should always be greater than the total supply of DSC
/// -> The collateral recorded by the engine should always match the tokens it actually holds
/// -> Every DSC in circulation should be backed by a user debt
/// -> Without price changes, no user should ever be below the minimum health factor

import {Test} from "forge-std/Test.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Handler} from "./Handler.t.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract InvariantsTest is Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, weth, wbtc) = deployer.run();

        //creating handler
        handler = new Handler(dscEngine, dsc);

        targetContract(address(handler));
        //the engine can't be a user of itself
        excludeSender(address(dscEngine));
    }

    //1st and most important invariant
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUSDValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUSDValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }

    //to check if the internal accounting is keeping good counts
    function invariant_collateralAccountingMatchesBalances() public view {
        address[] memory users = handler.getUserWithCollateralDeposited();
        uint256 sumWethDeposited;
        uint256 sumWbtcDeposited;

        for (uint256 i = 0; i < users.length; i++) {
            sumWethDeposited += dscEngine.getCollateralBalanceOfUser(users[i], weth);
            sumWbtcDeposited += dscEngine.getCollateralBalanceOfUser(users[i], wbtc);
        }

        assertEq(sumWethDeposited, IERC20(weth).balanceOf(address(dscEngine)));
        assertEq(sumWbtcDeposited, IERC20(wbtc).balanceOf(address(dscEngine)));
    }

    // same as before we have to check that our internal arithmetic stays conscistant
    // with external token contracts
    function invariant_totalMintedMatchesTotalSupply() public view {
        address[] memory users = handler.getUserWithCollateralDeposited();
        uint256 sumDSCMinted;
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 totalDSCMinted,) = dscEngine.getAccountInformation(users[i]);
            sumDSCMinted += totalDSCMinted;
        }

        assertEq(sumDSCMinted, dsc.totalSupply());
    }

    // in a "passive state", users should keep an helathy status
    function invariant_usersAreAlwaysHealthy() public view {
        address[] memory users = handler.getUserWithCollateralDeposited();
        for (uint256 i = 0; i < users.length; i++) {
            //witout price changing, users must always be healthy
            assertGe(dscEngine.getHealthFactor(users[i]), 1e18);
        }
    }
}
