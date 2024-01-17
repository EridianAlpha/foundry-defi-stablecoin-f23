//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {DSC} from "../src/DSC.sol";

// import {DSCEngine} from "../src/DSCEngine.sol";

contract DeployDSC is Script {
    function run() external returns (DSC) {
        vm.startBroadcast();
        DSC dsc = new DSC();
        vm.stopBroadcast();

        return dsc;
    }
}
