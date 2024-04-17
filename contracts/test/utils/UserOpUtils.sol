// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Test} from "forge-std/Test.sol";

contract UserOpUtils is Test {
    using MessageHashUtils for bytes32;

    // This function is used to pack a user operation with the given data.
    function packUserOp(address sender, uint256 nonce, bytes memory data)
        public
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 200000;
        uint128 callGasLimit = 50000;
        bytes32 gasLimits = bytes32((uint256(verificationGasLimit)) << 128 | uint256(callGasLimit));

        uint256 maxPriorityFeePerGas = 1 gwei;
        uint256 maxFeePerGas = 20 gwei;
        bytes32 gasFees = bytes32((uint256(maxPriorityFeePerGas)) << 128 | uint256(maxFeePerGas));

        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: "",
            callData: data,
            accountGasLimits: gasLimits,
            preVerificationGas: 21000,
            gasFees: gasFees,
            paymasterAndData: "",
            signature: ""
        });
    }

    function packUserOp(address sender, uint256 nonce, bytes memory initCode, bytes memory data)
        public
        pure
        returns (PackedUserOperation memory userOp)
    {
        uint128 verificationGasLimit = 500000;
        uint128 callGasLimit = 50000;
        bytes32 gasLimits = bytes32((uint256(verificationGasLimit)) << 128 | uint256(callGasLimit));

        uint256 maxPriorityFeePerGas = 1 gwei;
        uint256 maxFeePerGas = 20 gwei;
        bytes32 gasFees = bytes32((uint256(maxPriorityFeePerGas)) << 128 | uint256(maxFeePerGas));

        userOp = PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: initCode,
            callData: data,
            accountGasLimits: gasLimits,
            preVerificationGas: 21000,
            gasFees: gasFees,
            paymasterAndData: "",
            signature: ""
        });
    }

    // This function is used to hash a user operation.
    function hashUserOp(PackedUserOperation memory userOp) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                keccak256(userOp.paymasterAndData)
            )
        );
    }

    // This function is used to sign a user operation and return the signature. (ECDSA)
    function signUserOp(uint256 privateKey, bytes32 userOpHash) public pure returns (bytes memory) {
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function unpackHigh128(bytes32 packed) internal pure returns (uint256) {
        return uint256(packed) >> 128;
    }

    // unpack just the low 128-bits from a packed value
    function unpackLow128(bytes32 packed) internal pure returns (uint256) {
        return uint128(uint256(packed));
    }
}
