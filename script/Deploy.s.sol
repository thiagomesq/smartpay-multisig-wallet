// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SmartPayMultisig} from "src/SmartPayMultisig.sol";
import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    
    function run() external returns (SmartPayMultisig) {
        vm.startBroadcast(0xe7FDf6cA472c484FA8b7b2E11a5E62adaF1e649F);
        SmartPayMultisig smartPayMultisig = new SmartPayMultisig();
        vm.stopBroadcast();

        return smartPayMultisig;
    }
}
