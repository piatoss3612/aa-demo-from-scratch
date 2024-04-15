// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {BaseAccount} from "account-abstraction/core/BaseAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {TokenCallbackHandler} from "./TokenCallbackHandler.sol";

contract SimpleAccount is BaseAccount, TokenCallbackHandler, UUPSUpgradeable, Initializable {
    error InvalidInput();
    error OnlyOwner();
    error OnlyFromEntryPointOrOwner();

    using MessageHashUtils for bytes32;

    uint256 public constant SIG_VALIDATION_FAILED = 1;
    uint256 public constant SIG_VALIDATION_SUCCESS = 0;

    IEntryPoint private immutable _entryPoint;

    address public owner;

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    constructor(IEntryPoint entryPoint_) {
        _entryPoint = entryPoint_;
        _disableInitializers();
    }

    /*
        ===============
        | BaseAccount |
        ===============
    */

    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        virtual
        override
        returns (uint256 validationData)
    {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner != ECDSA.recover(hash, userOp.signature)) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /*
        =================
        | Initializable |
        =================
    */
    function initialize(address _owner) public virtual initializer {
        _initialize(_owner);
    }

    function _initialize(address _owner) internal virtual {
        owner = _owner;
        emit SimpleAccountInitialized(_entryPoint, _owner);
    }

    /*
        ==================
        | UUPSUpgradeable |
        ==================
    */

    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _onlyOwner();
    }

    /*
        =================
        | SimpleAccount |
        =================
    */
    function execute(address target, uint256 value, bytes memory data) external {
        _onlyFromEntryPointOrOwner();
        _call(target, value, data);
    }

    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas) external {
        _onlyFromEntryPointOrOwner();
        if (targets.length != datas.length || !(values.length == 0 || values.length != targets.length)) {
            revert InvalidInput();
        }
        if (values.length == 0) {
            for (uint256 i = 0; i < targets.length; i++) {
                _call(targets[i], 0, datas[i]);
            }
        } else {
            for (uint256 i = 0; i < targets.length; i++) {
                _call(targets[i], values[i], datas[i]);
            }
        }
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * check current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    /**
     * withdraw value from the account's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    /*
        =================
        | Helper Methods |
        =================
    */

    function _onlyOwner() internal view {
        //directly from EOA owner, or through the account itself (which gets redirected through execute())
        if (msg.sender != owner && msg.sender != address(this)) {
            revert OnlyOwner();
        }
    }

    function _onlyFromEntryPointOrOwner() internal view {
        if (msg.sender != address(entryPoint()) && msg.sender != owner) {
            revert OnlyFromEntryPointOrOwner();
        }
    }

    /*
        ============
        | Fallback |
        ============
    */
    receive() external payable {}
}
