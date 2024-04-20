// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {BLSAccount} from "account-abstraction/samples/bls/BLSAccount.sol";
import {BLSAccountFactory} from "account-abstraction/samples/bls/BLSAccountFactory.sol";
import {BLSSignatureAggregator} from "account-abstraction/samples/bls/BLSSignatureAggregator.sol";
import {BLSOpen} from "account-abstraction/samples/bls/lib/BLSOpen.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Counter} from "../src/Counter.sol";
import {UserOpUtils} from "./utils/UserOpUtils.sol";

contract BLSAggregatorTest is Test {
    EntryPoint public entryPoint;
    BLSSignatureAggregator public aggregator;
    BLSAccountFactory public factory;
    BLSAccount public impl;

    Counter public counter;
    UserOpUtils public utils;

    uint256 public ownerPrivateKey = uint256(keccak256("owner"));
    address public owner;
    address public deployer;
    address public beneficiary;

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        vm.label(owner, "Owner");
        vm.deal(owner, 100 ether);

        deployer = makeAddr("deployer");
        vm.label(deployer, "Deployer");
        vm.deal(deployer, 100 ether);

        beneficiary = makeAddr("beneficiary");
        vm.label(beneficiary, "Beneficiary");
        vm.deal(beneficiary, 1 ether);

        vm.startPrank(deployer);
        entryPoint = new EntryPoint();
        aggregator = new BLSSignatureAggregator(address(entryPoint));
        factory = new BLSAccountFactory(entryPoint, address(aggregator));
        impl = factory.accountImplementation();
        counter = new Counter();
        utils = new UserOpUtils();

        vm.label(address(entryPoint), "EntryPoint");
        vm.label(address(aggregator), "Aggregator");
        vm.label(address(factory), "Factory");
        vm.label(address(impl), "Implementation");
        vm.label(address(counter), "Counter");
        vm.label(address(utils), "Utils");

        aggregator.addStake{value: 1 ether}(2);
        vm.stopPrank();
    }
}
