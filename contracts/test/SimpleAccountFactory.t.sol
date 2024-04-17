// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {SimpleEntryPoint} from "../src/SimpleEntryPoint.sol";
import {SenderCreator} from "account-abstraction/core/SenderCreator.sol";
import {SimpleAccountFactory} from "../src/SimpleAccountFactory.sol";
import {SimpleAccount} from "../src/SimpleAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Counter} from "../src/Counter.sol";
import {UserOpUtils} from "./utils/UserOpUtils.sol";
import "./utils/Artifacts.sol";

contract SimpleAccountFactoryTest is Test {
    SimpleEntryPoint public entryPoint;
    SenderCreator public senderCreator;
    SimpleAccountFactory public factory;
    SimpleAccount public impl;
    Counter public counter;
    UserOpUtils public utils;

    uint256 public ownerPrivateKey = uint256(keccak256("owner"));
    address public owner;
    address public beneficiary;

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        vm.label(owner, "Owner");
        vm.deal(owner, 100 ether);

        beneficiary = makeAddr("beneficiary");
        vm.label(beneficiary, "Beneficiary");
        vm.deal(beneficiary, 1 ether);

        entryPoint = SimpleEntryPoint(payable(ENTRYPOINT_ADDRESS));
        vm.etch(address(entryPoint), ENTRYPOINT_BYTECODE);
        vm.label(address(entryPoint), "EntryPoint");

        senderCreator = SenderCreator(SENDERCREATOR_ADDRESS);
        vm.etch(address(senderCreator), SENDERCREATOR_BYTECODE);
        vm.label(address(senderCreator), "SenderCreator");

        factory = SimpleAccountFactory(FACTORY_ADDRESS);
        vm.etch(address(factory), FACTORY_BYTECODE);
        vm.label(address(factory), "SimpleAccountFactory");

        impl = SimpleAccount(payable(IMPL_ADDRESS));
        vm.etch(address(impl), IMPL_BYTECODE);
        vm.label(address(impl), "SimpleAccountImpl");

        vm.startPrank(beneficiary);
        counter = new Counter();
        vm.label(address(counter), "Counter");

        utils = new UserOpUtils();
        vm.label(address(utils), "UserOpUtils");
        vm.stopPrank();
    }

    function test_FactoryCreateAccount() public {
        uint256 salt = 10000;
        address expectedAddr = factory.getAddress(owner, salt);

        assertEq(expectedAddr.code.length, 0);

        SimpleAccount simpleAccount = factory.createAccount(owner, salt);

        assertEq(address(simpleAccount), expectedAddr);
        assertGt(expectedAddr.code.length, 0);
        assertEq(simpleAccount.owner(), owner);
        assertEq(address(simpleAccount.entryPoint()), address(entryPoint));
    }

    function test_handleOpsWithUndeployedAccount() public {
        uint256 salt = 10000;
        address expectedAddr = factory.getAddress(owner, salt);
        bytes memory initCode =
            abi.encodePacked(address(factory), abi.encodeWithSelector(factory.createAccount.selector, owner, salt));
        bytes memory callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector, address(counter), 0, abi.encodeWithSelector(counter.increment.selector)
        );
        uint256 nonce = entryPoint.getNonce(expectedAddr, 0);

        PackedUserOperation memory packedUserOp = utils.packUserOp(expectedAddr, nonce, initCode, callData);

        bytes32 userOpHash = entryPoint.getUserOpHash(packedUserOp);

        bytes memory signature = utils.signUserOp(ownerPrivateKey, userOpHash);

        packedUserOp.signature = signature;

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        vm.prank(owner);
        entryPoint.depositTo{value: 1 ether}(expectedAddr);

        uint256 counterBefore = counter.number();
        uint256 depositBefore = entryPoint.balanceOf(expectedAddr);
        uint256 beneficiaryBalanceBefore = beneficiary.balance;

        entryPoint.handleOps(ops, payable(beneficiary));

        assertEq(counter.number(), counterBefore + 1);
        assertGt(beneficiary.balance, beneficiaryBalanceBefore);
        assertLt(entryPoint.balanceOf(expectedAddr), depositBefore);
    }
}
