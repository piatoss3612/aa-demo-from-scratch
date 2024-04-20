// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccount} from "../src/SimpleAccount.sol";
import {SimpleAccountV2} from "../src/SimpleAccountV2.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Counter} from "../src/Counter.sol";
import {UserOpUtils} from "./utils/UserOpUtils.sol";
import "./utils/Artifacts.sol";

contract SimpleAccountTest is Test {
    bytes32 public constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    IEntryPoint public entryPoint;
    SimpleAccount public simpleAccountImpl;
    Counter public counter;
    UserOpUtils public utils;

    uint256 public ownerPrivateKey = 1;
    address public owner;
    address public deployer;
    address public bob;
    address public beneficiary;

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event UserOperationEvent(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 nonce,
        bool success,
        uint256 actualGasCost,
        uint256 actualGasUsed
    );

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        vm.label(owner, "Owner");
        vm.deal(owner, 100 ether);

        bob = makeAddr("bob");
        vm.label(bob, "Bob");

        deployer = makeAddr("deployer");
        vm.label(deployer, "Deployer");

        beneficiary = makeAddr("beneficiary");
        vm.label(beneficiary, "Beneficiary");
        vm.deal(beneficiary, 1 ether);

        entryPoint = IEntryPoint(payable(ENTRYPOINT_ADDRESS));
        vm.etch(address(entryPoint), ENTRYPOINT_BYTECODE);
        vm.label(address(entryPoint), "EntryPoint");

        simpleAccountImpl = SimpleAccount(payable(IMPL_ADDRESS));
        vm.etch(address(simpleAccountImpl), IMPL_BYTECODE);
        vm.label(address(simpleAccountImpl), "SimpleAccountImpl");

        vm.startPrank(deployer);
        counter = new Counter();
        vm.label(address(counter), "Counter");

        utils = new UserOpUtils();
        vm.label(address(utils), "UserOpUtils");
        vm.stopPrank();
    }

    function test_Deploy() public {
        bytes memory data = abi.encodeWithSelector(simpleAccountImpl.initialize.selector, owner);

        vm.expectEmit(true, true, true, true);
        emit SimpleAccountInitialized(entryPoint, owner);

        vm.prank(owner);
        ERC1967Proxy simpleAccountProxy = new ERC1967Proxy(address(simpleAccountImpl), data);

        // read the implementation address from the proxy contract
        address impl = address(uint160(uint256(vm.load(address(simpleAccountProxy), IMPLEMENTATION_SLOT))));

        assertEq(impl, address(simpleAccountImpl));

        SimpleAccount simpleAccount = SimpleAccount(payable(address(simpleAccountProxy)));

        assertEq(simpleAccount.owner(), owner);
        assertEq(address(simpleAccount.entryPoint()), address(entryPoint));
    }

    function test_OwnerExecute() public {
        SimpleAccount simpleAccount = createAccount();

        bytes memory userOp = abi.encodeWithSelector(counter.increment.selector);

        uint256 counterBefore = counter.number();

        vm.prank(owner);
        simpleAccount.execute(address(counter), 0, userOp);

        assertEq(counter.number(), counterBefore + 1);
    }

    function test_EntryPointExecute() public {
        SimpleAccount simpleAccount = createAccount();

        bytes memory userOp = abi.encodeWithSelector(counter.increment.selector);

        uint256 counterBefore = counter.number();

        vm.prank(address(entryPoint));
        simpleAccount.execute(address(counter), 0, userOp);

        assertEq(counter.number(), counterBefore + 1);
    }

    function test_RevertBobExecute() public {
        SimpleAccount simpleAccount = createAccount();

        bytes memory userOp = abi.encodeWithSelector(counter.increment.selector);

        vm.expectRevert();

        vm.prank(bob);
        simpleAccount.execute(address(counter), 0, userOp);
    }

    function test_AddDeposit() public {
        SimpleAccount simpleAccount = createAccount();

        uint256 amount = 10 ether;

        vm.prank(owner);
        simpleAccount.addDeposit{value: amount}();

        assertEq(simpleAccount.getDeposit(), amount);
    }

    function test_WithdrawDepositTo() public {
        SimpleAccount simpleAccount = createAccount();

        uint256 amount = 10 ether;

        vm.startPrank(owner);
        simpleAccount.addDeposit{value: amount}();

        assertEq(simpleAccount.getDeposit(), amount);

        simpleAccount.withdrawDepositTo(payable(owner), amount);
        vm.stopPrank();

        assertEq(simpleAccount.getDeposit(), 0);
    }

    function test_ValidateUserOp() public {
        SimpleAccount simpleAccount = createAccount();

        PackedUserOperation memory packedUserOp = utils.packUserOp(address(simpleAccount), simpleAccount.getNonce(), "");

        bytes32 userOpHash = entryPoint.getUserOpHash(packedUserOp);

        bytes memory signature = utils.signUserOp(ownerPrivateKey, userOpHash);

        packedUserOp.signature = signature;

        uint256 missingAccountFunds = 10 gwei;
        uint256 accountBalanceBefore = address(simpleAccount).balance;

        vm.prank(address(entryPoint));
        uint256 validationData = simpleAccount.validateUserOp(packedUserOp, userOpHash, missingAccountFunds);

        assertEq(validationData, 0);
        assertEq(address(entryPoint).balance, missingAccountFunds);
        assertEq(address(simpleAccount).balance, accountBalanceBefore - missingAccountFunds);
    }

    function test_HandleOps() public {
        SimpleAccount simpleAccount = createAccount();

        bytes memory callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector, address(counter), 0, abi.encodeWithSelector(counter.increment.selector)
        );

        uint256 nonce = simpleAccount.getNonce();

        PackedUserOperation memory packedUserOp = utils.packUserOp(address(simpleAccount), nonce, callData);

        bytes32 userOpHash = entryPoint.getUserOpHash(packedUserOp);

        bytes memory signature = utils.signUserOp(ownerPrivateKey, userOpHash);

        packedUserOp.signature = signature;

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        uint256 counterBefore = counter.number();
        uint256 accountBalanceBefore = address(simpleAccount).balance;
        uint256 beneficiaryBalanceBefore = beneficiary.balance;

        vm.expectEmit(true, true, true, false);
        emit UserOperationEvent(userOpHash, address(simpleAccount), address(0), nonce, true, 0, 0);

        entryPoint.handleOps(ops, payable(beneficiary));

        assertEq(counter.number(), counterBefore + 1);
        assertLt(address(simpleAccount).balance, accountBalanceBefore);
        assertGt(beneficiary.balance, beneficiaryBalanceBefore);
    }

    function test_HandleOpsWithFailedOp() public {
        SimpleAccount simpleAccount = createAccount();

        bytes memory callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector, address(counter), 0, abi.encodeWithSignature("decrement()")
        ); // call a non-existent function

        uint256 nonce = simpleAccount.getNonce();

        PackedUserOperation memory packedUserOp = utils.packUserOp(address(simpleAccount), nonce, callData);

        bytes32 userOpHash = entryPoint.getUserOpHash(packedUserOp);

        bytes memory signature = utils.signUserOp(ownerPrivateKey, userOpHash);

        packedUserOp.signature = signature;

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        uint256 counterBefore = counter.number();
        uint256 accountBalanceBefore = address(simpleAccount).balance;
        uint256 beneficiaryBalanceBefore = beneficiary.balance;

        bool success = false;

        vm.expectEmit(true, true, true, false);
        emit UserOperationEvent(userOpHash, address(simpleAccount), address(0), nonce, success, 0, 0);

        entryPoint.handleOps(ops, payable(beneficiary));

        assertEq(counter.number(), counterBefore);
        assertLt(address(simpleAccount).balance, accountBalanceBefore);
        assertGt(beneficiary.balance, beneficiaryBalanceBefore);
    }

    function test_HandleOpsWithExecuteBatch() public {
        SimpleAccount simpleAccount = createAccount();

        address[] memory targets = new address[](5);
        uint256[] memory values = new uint256[](0);
        bytes[] memory datas = new bytes[](5);

        bytes memory incrementData = abi.encodeWithSelector(counter.increment.selector);

        for (uint256 i = 0; i < 5; i++) {
            targets[i] = address(counter);
            datas[i] = incrementData;
        }

        bytes memory callData = abi.encodeWithSelector(SimpleAccount.executeBatch.selector, targets, values, datas);

        uint256 nonce = simpleAccount.getNonce();

        PackedUserOperation memory packedUserOp = utils.packUserOp(address(simpleAccount), nonce, callData);

        bytes32 userOpHash = entryPoint.getUserOpHash(packedUserOp);

        bytes memory signature = utils.signUserOp(ownerPrivateKey, userOpHash);

        packedUserOp.signature = signature;

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        uint256 counterBefore = counter.number();
        uint256 simpleAccountBalanceBefore = address(simpleAccount).balance;
        uint256 beneficiaryBalanceBefore = beneficiary.balance;

        vm.expectEmit(true, true, true, false);
        emit UserOperationEvent(userOpHash, address(simpleAccount), address(0), nonce, true, 0, 0);

        vm.prank(beneficiary);
        entryPoint.handleOps(ops, payable(beneficiary));

        assertEq(counter.number(), counterBefore + 5);
        assertLt(address(simpleAccount).balance, simpleAccountBalanceBefore);
        assertGt(beneficiary.balance, beneficiaryBalanceBefore);
    }

    function test_Upgrade() public {
        SimpleAccount simpleAccount = createAccount();

        string memory version = simpleAccount.version();

        assertEq(version, "1.0.0");

        vm.prank(deployer);
        SimpleAccountV2 simpleAccountV2Impl = new SimpleAccountV2(entryPoint);
        vm.label(address(simpleAccountV2Impl), "SimpleAccountV2Impl");

        bytes memory data = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(simpleAccountV2Impl), "");

        vm.prank(owner);
        (bool ok,) = address(simpleAccount).call(data);
        assertTrue(ok);

        version = simpleAccount.version();

        assertEq(version, "2.0.0");
    }

    function createAccount() public returns (SimpleAccount) {
        bytes memory data = abi.encodeWithSelector(simpleAccountImpl.initialize.selector, owner);

        vm.prank(owner);
        ERC1967Proxy simpleAccountProxy = new ERC1967Proxy(address(simpleAccountImpl), data);
        vm.deal(address(simpleAccountProxy), 1 ether);

        return SimpleAccount(payable(address(simpleAccountProxy)));
    }
}
