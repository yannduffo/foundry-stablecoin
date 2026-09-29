//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

/**
 * @title DeployDSC contract
 * @author Yann Duffo
 * @notice This script deploy a simple local DSC infrastructure :
 *         (DSC token + engine + 2 mock tokens + 2 mock price feeds)
 */
contract DeployDSC is Script {
    error DeployDSC__LocalOnly();

    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant ETH_USD_PRICE = 2000e8;
    int256 private constant BTC_USD_PRICE = 50000e8;

    function run() external returns (DecentralizedStableCoin dsc, DSCEngine engine, address weth, address wbtc) {
        if (block.chainid != 31337) revert DeployDSC__LocalOnly();

        vm.startBroadcast();
        //creating weth & wbtc mocks
        weth = address(new ERC20Mock());
        wbtc = address(new ERC20Mock());

        //creating price feeds mocks
        address wethFeed = address(new MockV3Aggregator(FEED_DECIMALS, ETH_USD_PRICE));
        address wbtcFeed = address(new MockV3Aggregator(FEED_DECIMALS, BTC_USD_PRICE));

        //creating token tables & feed tables
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = wbtc;
        address[] memory feeds = new address[](2);
        feeds[0] = wethFeed;
        feeds[1] = wbtcFeed;

        //creating dsc & dscEngine + transfer ownership of dsc to the engine
        dsc = new DecentralizedStableCoin();
        engine = new DSCEngine(tokens, feeds, address(dsc));
        dsc.transferOwnership(address(engine)); //from msg.sender to engine contract

        vm.stopBroadcast();
    }
}
