// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {BasePaymaster} from "account-abstraction/core/BasePaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {UserOperationLib} from "account-abstraction/core/UserOperationLib.sol";

contract SimplePaymaster is BasePaymaster {
    error SenderNotWhitelisted(address sender);
    error MaxCostExceeded(uint256 cost);

    using UserOperationLib for PackedUserOperation;

    uint256 constant SIG_VALIDATION_FAILED = 1;
    uint256 constant SIG_VALIDATION_SUCCESS = 0;

    uint256 private _maxCost;
    mapping(address => bool) private _whitelisted;

    event Whitelisted(address indexed account, bool state);
    event MaxCostChanged(uint256 maxCost);

    constructor(IEntryPoint _entryPoint, uint256 maxCost_) BasePaymaster(_entryPoint) {
        _maxCost = maxCost_;
    }

    function setWhitelisted(address account, bool state) external onlyOwner {
        _whitelisted[account] = state;
        emit Whitelisted(account, state);
    }

    function setWhitelistedBatch(address[] calldata accounts, bool state) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _whitelisted[accounts[i]] = state;
            emit Whitelisted(accounts[i], state);
        }
    }

    function isWhitelisted(address account) public view returns (bool) {
        return _whitelisted[account];
    }

    function setMaxCost(uint256 maxCost_) external onlyOwner {
        _maxCost = maxCost_;
        emit MaxCostChanged(maxCost_);
    }

    /**
     * Payment validation: check if paymaster agrees to pay.
     * Must verify sender is the entryPoint.
     * Revert to reject this request.
     * Note that bundlers will reject this method if it changes the state, unless the paymaster is trusted (whitelisted).
     * The paymaster pre-pays using its deposit, and receive back a refund after the postOp method returns.
     * @param userOp          - The user operation.
     * @param userOpHash      - Hash of the user's request data.
     * @param maxCost         - The maximum cost of this transaction (based on maximum gas and gas price from userOp).
     * @return context        - Value to send to a postOp. Zero length to signify postOp is not required.
     * @return validationData - Signature and time-range of this operation, encoded the same as the return
     *                          value of validateUserOperation.
     *                          <20-byte> sigAuthorizer - 0 for valid signature, 1 to mark signature failure,
     *                                                    other values are invalid for paymaster.
     *                          <6-byte> validUntil - last timestamp this operation is valid. 0 for "indefinite"
     *                          <6-byte> validAfter - first timestamp this operation is valid
     *                          Note that the validation code cannot use block.timestamp (or block.number) directly.
     */
    function _validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        (userOpHash); // silence warnings (unused variables)

        address sender = userOp.getSender();

        if (!isWhitelisted(sender)) {
            revert SenderNotWhitelisted(sender);
        }

        if (maxCost > _maxCost) {
            revert MaxCostExceeded(maxCost);
        }

        return (_encodeContext(sender), SIG_VALIDATION_SUCCESS);
    }

    /**
     * Post-operation handler.
     * Must verify sender is the entryPoint.
     * @param mode          - Enum with the following options:
     *                        opSucceeded - User operation succeeded.
     *                        opReverted  - User op reverted. The paymaster still has to pay for gas.
     *                        postOpReverted - never passed in a call to postOp().
     * @param context       - The context value returned by validatePaymasterUserOp
     * @param actualGasCost - Actual gas used so far (without this postOp call).
     * @param actualUserOpFeePerGas - the gas price this UserOp pays. This value is based on the UserOp's maxFeePerGas
     *                        and maxPriorityFee (and basefee)
     *                        It is not the same as tx.gasprice, which is what the bundler pays.
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        internal
        virtual
        override
    {
        (mode, actualGasCost, actualUserOpFeePerGas); // silence warnings (unused variables
        address sender = _decodeContext(context);

        if (!isWhitelisted(sender)) {
            revert SenderNotWhitelisted(sender);
        }
    }

    function _encodeContext(address sender) internal pure returns (bytes memory) {
        return abi.encode(sender);
    }

    function _decodeContext(bytes memory context) internal pure returns (address) {
        return abi.decode(context, (address));
    }
}
