// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleEntryPoint} from "../src/SimpleEntryPoint.sol";
import {SenderCreator} from "account-abstraction/core/SenderCreator.sol";
import {SimpleAccountFactory} from "../src/SimpleAccountFactory.sol";
import {SimpleAccount} from "../src/SimpleAccount.sol";
import "./utils/Artifacts.sol";

contract ArtifactsTest is Test {
    SimpleEntryPoint public entryPoint;
    SenderCreator public senderCreator;
    SimpleAccountFactory public factory;
    SimpleAccount public impl;

    function setUp() public {
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
        vm.label(address(impl), "SimpleAccount");
    }

    function test_ValidateArtifacts() public {
        assertEq(address(entryPoint.getSenderCreator()), address(senderCreator));
        assertEq(address(factory.accountImplementation()), address(impl));
        assertEq(address(impl.entryPoint()), address(entryPoint));
    }
}
