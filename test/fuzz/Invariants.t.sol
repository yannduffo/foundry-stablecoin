//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

/// What should be our invariants ?
/// -> The total supply of DSC should be less than the total value of collateral
/// -> Getter view function should never revert <- evergreen invariant

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

        //targetContract(address(dscEngine)); <- for openinvariants
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUSDValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUSDValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }

    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getCollateralTokens();
    }
}
