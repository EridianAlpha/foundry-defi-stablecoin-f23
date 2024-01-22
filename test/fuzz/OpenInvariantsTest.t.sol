// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSC} from "../../src/DSC.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Not used as the data is too random and doesn't take into consideration the complex logic of the DSC
contract InvariantTests is StdInvariant, Test {
// DeployDSC deployer;
// DSCEngine dscEngine;
// DSC dsc;
// HelperConfig helperConfig;
// address weth;
// address wbtc;

// function setUp() external {
//     DeployDSC deployer = new DeployDSC();
//     (dsc, dscEngine, helperConfig) = deployer.run();
//     (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
//     targetContract(address(dscEngine));
// }

// function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//     uint256 totalSupply = dsc.totalSupply();
//     uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
//     uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
//     uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
//     uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

//     console.log("wethValue: %s", wethValue);
//     console.log("wbtcValue: %s", wbtcValue);
//     console.log("totalSupply: %s", totalSupply);

//     assert(wethValue + wbtcValue >= totalSupply);
// }
}
