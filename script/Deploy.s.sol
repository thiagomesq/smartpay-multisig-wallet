// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SmartPayMultisig} from "src/SmartPayMultisig.sol";
import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    
    function run() external returns (SmartPayMultisig) {
        vm.startBroadcast();
        SmartPayMultisig smartPayMultisig = new SmartPayMultisig();
        vm.stopBroadcast();

        return smartPayMultisig;
    }
}
