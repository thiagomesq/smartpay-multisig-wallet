// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title SmartPayMultisig
 * @author Thiago Mesquita
 * @notice A simple multi-signature wallet with weighted voting.
 * @dev This contract allows multiple owners to manage funds and execute transactions based on weighted confirmations.
 */
// aderyn-fp-next-line(centralization-risk)
contract SmartPayMultisig is AccessControl {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /**
     * @notice Thrown when trying to access a transaction that does not exist.
     */
    error SmartPayMultisig__TxDoesNotExist();
    /**
     * @notice Thrown when trying to modify a transaction that has already been executed.
     */
    error SmartPayMultisig__TxAlreadyExecuted();
    /**
     * @notice Thrown when an owner tries to confirm a transaction they have already confirmed.
     */
    error SmartPayMultisig__TxAlreadyConfirmed();
    /**
     * @notice Thrown when an owner tries to revoke a confirmation for a transaction they have not confirmed.
     */
    error SmartPayMultisig__TxNotConfirmed();
    /**
     * @notice Thrown when trying to execute a transaction that has not met the required confirmation threshold.
     */
    error SmartPayMultisig__CannotExecuteTx();
    /**
     * @notice Thrown when a transaction execution fails.
     */
    error SmartPayMultisig__TxFailed();
    /**
     * @notice Thrown when an owner does not exist.
     */
    error SmartPayMultisig__OwnerDoesNotExist();

    /**
     * @dev Represents a transaction proposed by an owner.
     * @param to The destination address of the transaction.
     * @param value The amount of ETH to be sent.
     * @param data The calldata for the transaction.
     * @param executed A flag indicating whether the transaction has been executed.
     * @param weightConfirmations The total weight of confirmations received.
     */
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint8 weightConfirmations;
    }

    /// @dev The minimum weight of confirmations required to execute a transaction.
    uint8 private s_weightConfirmationsRequired = 66;
    /// @dev An array containing the addresses of all owners.
    address[] private s_owners;
    /// @dev A mapping from an owner's address to their voting weight.
    mapping(address => uint8) private s_ownerWeights;
    /// @dev A nested mapping to track confirmations for each transaction by each owner.
    mapping(uint256 => mapping(address => bool)) private s_isConfirmed;
    /// @dev An array of all transactions submitted to the wallet.
    Transaction[] private s_transactions;

    /**
     * @notice Emitted when ETH is deposited into the contract.
     * @param sender The address of the depositor.
     * @param amount The amount of ETH deposited.
     * @param balance The new balance of the contract.
     */
    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    /**
     * @notice Emitted when a new transaction is submitted.
     * @param owner The owner who submitted the transaction.
     * @param txIndex The index of the new transaction.
     * @param to The destination address of the transaction.
     * @param value The amount of ETH to be sent.
     * @param data The calldata for the transaction.
     */
    event SubmitTransaction(
        address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data
    );
    /**
     * @notice Emitted when an owner confirms a transaction.
     * @param owner The owner who confirmed the transaction.
     * @param txIndex The index of the confirmed transaction.
     */
    event ConfirmTransaction(address indexed owner, uint256 indexed txIndex);
    /**
     * @notice Emitted when an owner revokes their confirmation of a transaction.
     * @param owner The owner who revoked the confirmation.
     * @param txIndex The index of the transaction.
     */
    event RevokeConfirmation(address indexed owner, uint256 indexed txIndex);
    /**
     * @notice Emitted when a transaction is executed.
     * @param owner The owner who executed the transaction.
     * @param txIndex The index of the executed transaction.
     */
    event ExecuteTransaction(address indexed owner, uint256 indexed txIndex);
    /**
     * @notice Emitted when a new owner is added to the contract.
     * @param owner The address of the new owner.
     * @param weight The voting weight of the new owner.
     */
    event AddOwner(address caller, address indexed owner, uint8 weight);
    /**
     * @notice Emitted when the minimum weight of confirmations required to execute a transaction is set.
     * @param weightConfirmationsRequired The new minimum weight of confirmations required.
     */
    event SetWeightConfirmationsRequired(uint8 indexed weightConfirmationsRequired);
    /**
     * @notice Emitted when an owner is removed from the contract.
     * @param owner The address of the owner to remove.
     */
    event RemoveOwner(address caller, address indexed owner);

    /**
     * @dev Modifier to check if a transaction exists.
     * @param _txIndex The index of the transaction to check.
     */
    modifier txExists(uint256 _txIndex) {
        if (_txIndex >= s_transactions.length) {
            revert SmartPayMultisig__TxDoesNotExist();
        }
        _;
    }

    /**
     * @dev Modifier to check if a transaction has not been executed yet.
     * @param _txIndex The index of the transaction to check.
     */
    modifier notExecuted(uint256 _txIndex) {
        if (s_transactions[_txIndex].executed) {
            revert SmartPayMultisig__TxAlreadyExecuted();
        }
        _;
    }

    /**
     * @dev Modifier to check if the caller has not already confirmed the transaction.
     * @param _txIndex The index of the transaction to check.
     */
    modifier notConfirmed(uint256 _txIndex) {
        if (s_isConfirmed[_txIndex][msg.sender]) {
            revert SmartPayMultisig__TxAlreadyConfirmed();
        }
        _;
    }

    modifier ownerExists(address _owner) {
        if (!hasRole(OWNER_ROLE, _owner)) {
            revert SmartPayMultisig__OwnerDoesNotExist();
        }
        _;
    }

    /// @notice Initializes the contract with the contract owner.
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Allows the contract to receive ETH.
     */
    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    /**
     * @notice Adds a new owner to the contract and sets their voting weight.
     * @param _owner The address of the new owner.
     * @param _weight The voting weight of the new owner.
     */
    function addOwnerAndSetWeight(address _owner, uint8 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_owners.push(_owner);
        s_ownerWeights[_owner] = _weight;
        _grantRole(OWNER_ROLE, _owner);
        emit AddOwner(msg.sender, _owner, _weight);
    }

    /**
     * @notice Removes an owner from the contract.
     * @param _owner The address of the owner to remove.
     */
    function removeOwner(address _owner) external onlyRole(DEFAULT_ADMIN_ROLE) ownerExists(_owner) {
        _revokeRole(OWNER_ROLE, _owner);
        emit RemoveOwner(msg.sender, _owner);
    }

    /**
     * @notice Sets the minimum weight of confirmations required to execute a transaction.
     * @param _weightConfirmationsRequired The new minimum weight of confirmations required.
     */
    function setWeightConfirmationsRequired(uint8 _weightConfirmationsRequired) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_weightConfirmationsRequired = _weightConfirmationsRequired;
        emit SetWeightConfirmationsRequired(_weightConfirmationsRequired);
    }

    /**
     * @notice Submit a new transaction to the contract.
     * @param _to The destination address of the transaction.
     * @param _value The amount of ETH to be sent.
     * @param _data The calldata for the transaction.
     */
    function submitTransaction(address _to, uint256 _value, bytes memory _data) external onlyRole(OWNER_ROLE) {
        uint256 txIndex = s_transactions.length;

        s_transactions.push(Transaction({to: _to, value: _value, data: _data, executed: false, weightConfirmations: 0}));

        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }

    /**
     * @notice Confirm a transaction.
     * @param _txIndex The index of the transaction to confirm.
     */
    function confirmTransaction(uint256 _txIndex)
        external
        onlyRole(OWNER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = s_transactions[_txIndex];
        transaction.weightConfirmations += s_ownerWeights[msg.sender];
        s_isConfirmed[_txIndex][msg.sender] = true;

        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    /**
     * @notice Execute a confirmed transaction.
     * @param _txIndex The index of the transaction to execute.
     */
    function executeTransaction(uint256 _txIndex)
        external
        onlyRole(OWNER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = s_transactions[_txIndex];

        if (transaction.weightConfirmations < s_weightConfirmationsRequired) {
            revert SmartPayMultisig__CannotExecuteTx();
        }

        if (transaction.to == address(0)) {
            revert SmartPayMultisig__CannotExecuteTx();
        }

        transaction.executed = true;

        (bool success,) = transaction.to.call{value: transaction.value}(transaction.data);
        if (!success) {
            revert SmartPayMultisig__TxFailed();
        }

        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    /**
     * @notice Revoke a confirmation for a transaction.
     * @param _txIndex The index of the transaction to revoke confirmation for.
     */
    function revokeConfirmation(uint256 _txIndex)
        external
        onlyRole(OWNER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = s_transactions[_txIndex];

        if (!s_isConfirmed[_txIndex][msg.sender]) {
            revert SmartPayMultisig__TxNotConfirmed();
        }

        transaction.weightConfirmations -= s_ownerWeights[msg.sender];
        s_isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    /**
     * @notice Get the minimum weight of confirmations required to execute a transaction.
     * @return The minimum weight of confirmations required.
     */
    function getWeightConfirmationsRequired() external view onlyRole(DEFAULT_ADMIN_ROLE) returns (uint8) {
        return s_weightConfirmationsRequired;
    }

    /**
     * @notice Get the list of all owners.
     * @return The list of all owners.
     */
    function getOwners() external view onlyRole(DEFAULT_ADMIN_ROLE) returns (address[] memory) {
        return s_owners;
    }

    /**
     * @notice Get the voting weight of an owner.
     * @param _owner The address of the owner to check.
     * @return The voting weight of the owner.
     */
    function getOwnerWeight(address _owner)
        external
        view
        onlyRole(DEFAULT_ADMIN_ROLE)
        ownerExists(_owner)
        returns (uint8)
    {
        return s_ownerWeights[_owner];
    }

    /**
     * @notice Get the confirmation status of a transaction for the caller.
     * @param _txIndex The index of the transaction to check.
     * @return The confirmation status of the transaction for the caller.
     */
    function getConfirmed(uint256 _txIndex) external view onlyRole(OWNER_ROLE) returns (bool) {
        return s_isConfirmed[_txIndex][msg.sender];
    }

    /**
     * @notice Get the confirmation status of a transaction for a specific owner.
     * @param _txIndex The index of the transaction to check.
     * @param _owner The address of the owner to check.
     * @return The confirmation status of the transaction for a specific owner.
     */
    function getConfirmed(uint256 _txIndex, address _owner) external view onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        return s_isConfirmed[_txIndex][_owner];
    }

    /**
     * @notice Get the number of transactions submitted to the contract.
     * @return The number of transactions submitted to the contract.
     */
    function getTransactionCount() external view onlyRole(OWNER_ROLE) returns (uint256) {
        return s_transactions.length;
    }

    /**
     * @notice Retrieves the details of a specific transaction.
     * @param _txIndex The index of the transaction to retrieve.
     * @return transaction The transaction details.
     */
    function getTransaction(uint256 _txIndex)
        external
        view
        onlyRole(OWNER_ROLE)
        txExists(_txIndex)
        returns (Transaction memory)
    {
        return s_transactions[_txIndex];
    }
}
