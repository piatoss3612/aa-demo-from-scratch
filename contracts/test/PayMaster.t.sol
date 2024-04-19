// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {SimpleEntryPoint} from "../src/SimpleEntryPoint.sol";
import {SenderCreator} from "account-abstraction/core/SenderCreator.sol";
import {SimpleAccountFactory} from "../src/SimpleAccountFactory.sol";
import {SimpleAccount} from "../src/SimpleAccount.sol";
import {SimplePaymaster} from "../src/SimplePaymaster.sol";
import {LegacyTokenPaymaster} from "account-abstraction/samples/LegacyTokenPaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Counter} from "../src/Counter.sol";
import {UserOpUtils} from "./utils/UserOpUtils.sol";
import "./utils/Artifacts.sol";

contract PaymasterTest is Test {
    error SenderNotWhitelisted(address sender);
    error FailedOp(uint256 opIndex, string reason);
    error FailedOpWithRevert(uint256 opIndex, string reason, bytes inner);

    uint256 public constant SALT = 10000;
    uint256 public constant INITIAL_MAX_COST = 1 ether;
    uint256 public constant PAYMASTER_DEPOSIT = 10 ether;

    SimpleEntryPoint public entryPoint;
    SenderCreator public senderCreator;
    SimpleAccountFactory public factory;
    SimpleAccount public impl;
    SimplePaymaster public paymaster;
    LegacyTokenPaymaster public tokenPaymaster;
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

        vm.startPrank(deployer);
        paymaster = new SimplePaymaster(entryPoint, INITIAL_MAX_COST);
        vm.label(address(paymaster), "Paymaster");

        tokenPaymaster = new LegacyTokenPaymaster(address(factory), "LTP", entryPoint);
        vm.label(address(tokenPaymaster), "LegacyTokenPaymaster");

        counter = new Counter();
        vm.label(address(counter), "Counter");

        utils = new UserOpUtils();
        vm.label(address(utils), "UserOpUtils");

        paymaster.deposit{value: PAYMASTER_DEPOSIT}();
        tokenPaymaster.deposit{value: PAYMASTER_DEPOSIT}();

        vm.stopPrank();

        assertEq(entryPoint.balanceOf(address(paymaster)), PAYMASTER_DEPOSIT);
    }

    function test_HandleOpsWithWhitelistedAccountAndEthPayment() public {
        SimpleAccount account = factory.createAccount(owner, SALT);
        PackedUserOperation[] memory ops = getrUserOps(address(account), address(paymaster));

        vm.prank(deployer);
        paymaster.setWhitelisted(address(account), true);

        uint256 counterBefore = counter.number();
        uint256 depositBefore = entryPoint.balanceOf(address(paymaster));
        uint256 beneficiaryBalanceBefore = beneficiary.balance;

        entryPoint.handleOps(ops, payable(beneficiary));

        assertEq(counter.number(), counterBefore + 1);
        assertLt(entryPoint.balanceOf(address(paymaster)), depositBefore);
        assertGt(beneficiary.balance, beneficiaryBalanceBefore);
    }

    function test_RevertHandleOpsWithNotWhitelistedAccount() public {
        SimpleAccount account = factory.createAccount(owner, SALT);
        PackedUserOperation[] memory ops = getrUserOps(address(account), address(paymaster));

        bytes memory innerError = abi.encodeWithSelector(SenderNotWhitelisted.selector, address(account));

        vm.expectRevert(abi.encodeWithSelector(FailedOpWithRevert.selector, 0, "AA33 reverted", innerError));
        entryPoint.handleOps(ops, payable(beneficiary));
    }

    function test_RevertHandleOpsWithInsufficientDeposit() public {
        SimpleAccount account = factory.createAccount(owner, SALT);
        PackedUserOperation[] memory ops = getrUserOps(address(account), address(paymaster));

        vm.startPrank(deployer);
        paymaster.setWhitelisted(address(account), true);
        paymaster.withdrawTo(payable(deployer), PAYMASTER_DEPOSIT);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(FailedOp.selector, 0, "AA31 paymaster deposit too low"));
        entryPoint.handleOps(ops, payable(beneficiary));
    }

    function test_HandleOpsWithLegacyTokenPayment() public {
        SimpleAccount account = factory.createAccount(owner, SALT);
        PackedUserOperation[] memory ops = getrUserOps(address(account), address(tokenPaymaster));

        vm.prank(deployer);
        tokenPaymaster.mintTokens(address(account), 1 ether);

        assertEq(tokenPaymaster.balanceOf(address(account)), 1 ether);

        uint256 counterBefore = counter.number();
        uint256 depositBefore = entryPoint.balanceOf(address(tokenPaymaster));
        uint256 accountTokenBalanceBefore = tokenPaymaster.balanceOf(address(account));
        uint256 beneficiaryBalanceBefore = beneficiary.balance;

        entryPoint.handleOps(ops, payable(beneficiary));

        assertEq(counter.number(), counterBefore + 1);
        assertLt(entryPoint.balanceOf(address(tokenPaymaster)), depositBefore);
        assertLt(tokenPaymaster.balanceOf(address(account)), accountTokenBalanceBefore);
        assertGt(beneficiary.balance, beneficiaryBalanceBefore);
    }

    function test_RevertHandleOpsWithInsufficientTokenBalance() public {
        SimpleAccount account = factory.createAccount(owner, SALT);
        PackedUserOperation[] memory ops = getrUserOps(address(account), address(tokenPaymaster));

        vm.expectRevert();
        entryPoint.handleOps(ops, payable(beneficiary));
    }

    function getrUserOps(address accountAddr, address paymasterAddr)
        internal
        view
        returns (PackedUserOperation[] memory)
    {
        uint256 nonce = entryPoint.getNonce(accountAddr, 0);

        bytes memory callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector, address(counter), 0, abi.encodeWithSelector(counter.increment.selector)
        );

        PackedUserOperation memory packedUserOp = utils.packUserOp(accountAddr, nonce, callData);

        bytes memory paymasterAndData = utils.packPaymasterAndData(address(paymasterAddr), 15000, 20000);

        packedUserOp.paymasterAndData = paymasterAndData;

        bytes32 userOpHash = entryPoint.getUserOpHash(packedUserOp);

        bytes memory signature = utils.signUserOp(ownerPrivateKey, userOpHash);

        packedUserOp.signature = signature;

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        return ops;
    }
}
