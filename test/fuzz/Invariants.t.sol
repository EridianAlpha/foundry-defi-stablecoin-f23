// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSC} from "../../src/DSC.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

// Not used as the data is too random and doesn't take into consideration the complex logic of the DSC
contract Invariants is StdInvariant, Test {
    Handler handler;
    DeployDSC deployer;
    DSCEngine dscEngine;
    DSC dsc;
    HelperConfig helperConfig;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);
        console.log("totalSupply: %s", totalSupply);
        console.log("Times mint called", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getMinHealthFactor();
    }
}
