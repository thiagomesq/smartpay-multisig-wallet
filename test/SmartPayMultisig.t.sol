// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {SmartPayMultisig} from "../src/SmartPayMultisig.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract SmartPayMultisigTest is Test {
    SmartPayMultisig private s_smartPayMultisig;

    address private s_contractOwner;
    address private s_owner1;
    address private s_owner2;

    uint8 private constant WEIGHT_1 = 50;
    uint8 private constant WEIGHT_2 = 50;

    uint256 private s_txIndex;

    function setUp() public {
        s_smartPayMultisig = new SmartPayMultisig();
        s_contractOwner = address(this);

        s_owner1 = makeAddr("owner1");
        s_owner2 = makeAddr("owner2");

        vm.prank(s_contractOwner);
        s_smartPayMultisig.addOwnerAndSetWeight(s_owner1, WEIGHT_1);

        vm.prank(s_contractOwner);
        s_smartPayMultisig.addOwnerAndSetWeight(s_owner2, WEIGHT_2);
    }

    function test_CorrectInitialStateAfterSetup() public view {
        assertEq(s_smartPayMultisig.getTransactionCount(), 0, "Initial transaction count should be 0");

        address[] memory owners = s_smartPayMultisig.getOwners();
        assertEq(owners.length, 2, "There should be 2 owners after setup");
        assertEq(owners[0], s_owner1, "Owner 1 should be the first owner added");
        assertEq(owners[1], s_owner2, "Owner 2 should be the second owner added");
    }

    function testFuzz_addOwnerAndSetWeight(address _newOwner, uint8 _weight) public {
        vm.assume(_newOwner != address(0));

        vm.startPrank(s_owner1);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        s_smartPayMultisig.addOwnerAndSetWeight(_newOwner, _weight);
        vm.stopPrank();

        vm.startPrank(s_contractOwner);
        s_smartPayMultisig.addOwnerAndSetWeight(_newOwner, _weight);
        vm.stopPrank();

        address[] memory owners = s_smartPayMultisig.getOwners();
        assertEq(owners.length, 3, "Should have 3 owners after adding a new one");
        assertEq(owners[2], _newOwner, "The new owner should be the last in the list");
    }

    function testFuzz_setWeightConfirmationsRequired(uint8 _newConfirmations) public {
        vm.assume(_newConfirmations > 0 && _newConfirmations <= 100);

        vm.startPrank(s_owner1);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        s_smartPayMultisig.setWeightConfirmationsRequired(_newConfirmations);
        vm.stopPrank();

        vm.startPrank(s_contractOwner);
        vm.expectEmit(true, true, true, true);
        emit SmartPayMultisig.SetWeightConfirmationsRequired(_newConfirmations);
        s_smartPayMultisig.setWeightConfirmationsRequired(_newConfirmations);
        vm.stopPrank();
    }

    function testFuzz_submitTransaction(address _to, uint256 _value, bytes memory _data) public {
        vm.assume(_to != address(0));
        address nonOwner = makeAddr("nonOwner");

        // Revert if a non-owner tries to submit
        vm.startPrank(nonOwner);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        s_smartPayMultisig.submitTransaction(_to, _value, _data);
        vm.stopPrank();

        // Success case
        vm.startPrank(s_owner1);
        uint256 txIndex = s_smartPayMultisig.getTransactionCount();
        vm.expectEmit(true, true, true, true);
        emit SmartPayMultisig.SubmitTransaction(s_owner1, txIndex, _to, _value, _data);
        s_smartPayMultisig.submitTransaction(_to, _value, _data);
        vm.stopPrank();

        assertEq(s_smartPayMultisig.getTransactionCount(), txIndex + 1, "Transaction count should increment");

        SmartPayMultisig.Transaction memory transaction = s_smartPayMultisig.getTransaction(txIndex);

        assertEq(transaction.to, _to, "Transaction 'to' address is incorrect");
        assertEq(transaction.value, _value, "Transaction 'value' is incorrect");
        assertEq(keccak256(transaction.data), keccak256(_data), "Transaction 'data' is incorrect");
        assertFalse(transaction.executed, "Transaction should not be executed yet");
        assertEq(transaction.weightConfirmations, 0, "Transaction should have 0 confirmations initially");
    }

    // Helper function to submit a generic transaction for other tests
    function _submitTransaction() private {
        vm.startPrank(s_owner1);
        s_txIndex = s_smartPayMultisig.getTransactionCount();
        s_smartPayMultisig.submitTransaction(makeAddr("recipient"), 1 ether, "");
        vm.stopPrank();
    }

    function test_confirmTransaction_Reverts() public {
        _submitTransaction();

        // Revert if non-owner tries to confirm
        vm.startPrank(makeAddr("nonOwner"));
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        s_smartPayMultisig.confirmTransaction(s_txIndex);
        vm.stopPrank();

        // Revert if tx does not exist
        vm.startPrank(s_owner1);
        vm.expectRevert(SmartPayMultisig.SmartPayMultisig__TxDoesNotExist.selector);
        s_smartPayMultisig.confirmTransaction(s_txIndex + 1);

        // Revert if already confirmed
        s_smartPayMultisig.confirmTransaction(s_txIndex);
        vm.expectRevert(SmartPayMultisig.SmartPayMultisig__TxAlreadyConfirmed.selector);
        s_smartPayMultisig.confirmTransaction(s_txIndex);
        vm.stopPrank();
    }

    function test_confirmTransaction_Success() public {
        _submitTransaction();

        vm.startPrank(s_owner2);
        vm.expectEmit(true, true, false, false);
        emit SmartPayMultisig.ConfirmTransaction(s_owner2, s_txIndex);
        s_smartPayMultisig.confirmTransaction(s_txIndex);
        vm.stopPrank();

        SmartPayMultisig.Transaction memory transaction = s_smartPayMultisig.getTransaction(s_txIndex);
        assertEq(
            transaction.weightConfirmations,
            WEIGHT_2,
            "Confirmations should be equal to the weight of the confirming owner"
        );
    }

    function test_confirmTransaction_RevertsIfExecuted() public {
        _submitTransaction();

        vm.deal(address(s_smartPayMultisig), 1 ether);

        vm.startPrank(s_contractOwner);
        s_smartPayMultisig.setWeightConfirmationsRequired(WEIGHT_1 + WEIGHT_2);
        vm.stopPrank();

        vm.startPrank(s_owner1);
        s_smartPayMultisig.confirmTransaction(s_txIndex);
        vm.stopPrank();

        vm.startPrank(s_owner2);
        s_smartPayMultisig.confirmTransaction(s_txIndex);
        s_smartPayMultisig.executeTransaction(s_txIndex);
        vm.stopPrank();

        // Revert if tx is already executed
        address owner3 = makeAddr("owner3");
        vm.startPrank(s_contractOwner);
        s_smartPayMultisig.addOwnerAndSetWeight(owner3, 10);
        vm.stopPrank();

        vm.startPrank(owner3);
        vm.expectRevert(SmartPayMultisig.SmartPayMultisig__TxAlreadyExecuted.selector);
        s_smartPayMultisig.confirmTransaction(s_txIndex);
        vm.stopPrank();
    }

    function test_revokeConfirmation_Reverts() public {
        _submitTransaction();

        // Revert if non-owner tries to revoke
        vm.startPrank(makeAddr("nonOwner"));
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        s_smartPayMultisig.revokeConfirmation(s_txIndex);
        vm.stopPrank();

        // Revert if tx does not exist
        vm.startPrank(s_owner1);
        vm.expectRevert(SmartPayMultisig.SmartPayMultisig__TxDoesNotExist.selector);
        s_smartPayMultisig.revokeConfirmation(s_txIndex + 1);

        // Revert if not confirmed yet
        vm.expectRevert(SmartPayMultisig.SmartPayMultisig__TxNotConfirmed.selector);
        s_smartPayMultisig.revokeConfirmation(s_txIndex);
        vm.stopPrank();
    }

    function test_revokeConfirmation_Success() public {
        _submitTransaction();

        vm.startPrank(s_owner1);
        s_smartPayMultisig.confirmTransaction(s_txIndex);
        vm.stopPrank();

        SmartPayMultisig.Transaction memory transaction = s_smartPayMultisig.getTransaction(s_txIndex);
        assertEq(transaction.weightConfirmations, WEIGHT_1, "Confirmations should be WEIGHT_1 before revoking");

        vm.startPrank(s_owner1);
        vm.expectEmit(true, true, false, false);
        emit SmartPayMultisig.RevokeConfirmation(s_owner1, s_txIndex);
        s_smartPayMultisig.revokeConfirmation(s_txIndex);
        vm.stopPrank();

        transaction = s_smartPayMultisig.getTransaction(s_txIndex);
        assertEq(transaction.weightConfirmations, 0, "Confirmations should be 0 after revoking");
    }

    function test_executeTransaction_Reverts() public {
        _submitTransaction();

        // Revert if non-owner tries to execute
        vm.startPrank(makeAddr("nonOwner"));
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        s_smartPayMultisig.executeTransaction(s_txIndex);
        vm.stopPrank();

        // Revert if tx does not exist
        vm.startPrank(s_owner1);
        vm.expectRevert(SmartPayMultisig.SmartPayMultisig__TxDoesNotExist.selector);
        s_smartPayMultisig.executeTransaction(s_txIndex + 1);

        // Revert if not enough confirmations
        vm.expectRevert(SmartPayMultisig.SmartPayMultisig__CannotExecuteTx.selector);
        s_smartPayMultisig.executeTransaction(s_txIndex);
        vm.stopPrank();
    }

    function test_executeTransaction_Success() public {
        _submitTransaction();
        address recipient = makeAddr("recipient");
        uint256 startingBalance = recipient.balance;

        vm.deal(address(s_smartPayMultisig), 1 ether);

        vm.startPrank(s_contractOwner);
        s_smartPayMultisig.setWeightConfirmationsRequired(WEIGHT_1 + WEIGHT_2);
        vm.stopPrank();

        vm.startPrank(s_owner1);
        s_smartPayMultisig.confirmTransaction(s_txIndex);
        vm.stopPrank();

        vm.startPrank(s_owner2);
        s_smartPayMultisig.confirmTransaction(s_txIndex);

        vm.expectEmit(true, true, false, false);
        emit SmartPayMultisig.ExecuteTransaction(s_owner2, s_txIndex);
        s_smartPayMultisig.executeTransaction(s_txIndex);
        vm.stopPrank();

        SmartPayMultisig.Transaction memory transaction = s_smartPayMultisig.getTransaction(s_txIndex);
        assertTrue(transaction.executed, "Transaction should be marked as executed");
        assertEq(recipient.balance, startingBalance + 1 ether, "Recipient should have received 1 ether");

        // Revert if already executed
        vm.startPrank(s_owner1);
        vm.expectRevert(SmartPayMultisig.SmartPayMultisig__TxAlreadyExecuted.selector);
        s_smartPayMultisig.executeTransaction(s_txIndex);
        vm.stopPrank();
    }

    function test_receive() public {
        address depositor = makeAddr("depositor");
        uint256 amount = 1 ether;

        uint256 initialBalance = address(s_smartPayMultisig).balance;

        vm.startPrank(depositor);
        vm.deal(depositor, amount);

        vm.expectEmit(true, false, false, false);
        emit SmartPayMultisig.Deposit(depositor, amount, initialBalance + amount);

        (bool success,) = address(s_smartPayMultisig).call{value: amount}("");
        assertTrue(success, "Receive function call failed");
        vm.stopPrank();

        uint256 finalBalance = address(s_smartPayMultisig).balance;
        assertEq(
            finalBalance, initialBalance + amount, "Contract balance should have increased by the deposited amount"
        );
    }
}
