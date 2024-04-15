// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccount} from "../src/SimpleAccount.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Counter} from "../src/Counter.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SimpleAccountTest is Test {
    using MessageHashUtils for bytes32;

    bytes32 public constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    EntryPoint public entryPoint;
    SimpleAccount public simpleAccountImpl;
    Counter public counter;

    uint256 public ownerPrivateKey = 1;
    address public owner;
    address public bob;

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        vm.label(owner, "Owner");
        vm.deal(owner, 100 ether);

        bob = makeAddr("bob");
        vm.label(bob, "Bob");

        entryPoint = new EntryPoint();
        vm.label(address(entryPoint), "EntryPoint");

        simpleAccountImpl = new SimpleAccount(entryPoint);
        vm.label(address(simpleAccountImpl), "SimpleAccountImpl");

        counter = new Counter();
        vm.label(address(counter), "Counter");
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

        vm.expectRevert(SimpleAccount.OnlyFromEntryPointOrOwner.selector);

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

        bytes memory userOp = abi.encodeWithSelector(counter.increment.selector);

        PackedUserOperation memory packedUserOp = PackedUserOperation({
            sender: owner,
            nonce: simpleAccount.getNonce(),
            initCode: "",
            callData: userOp,
            accountGasLimits: bytes32(uint256(20 gwei)),
            preVerificationGas: 10 gwei,
            gasFees: bytes32(uint256(2 gwei)),
            paymasterAndData: "",
            signature: ""
        });

        bytes32 userOpHash = keccak256(
            abi.encode(
                packedUserOp.sender,
                packedUserOp.nonce,
                keccak256(packedUserOp.initCode),
                keccak256(packedUserOp.callData),
                packedUserOp.accountGasLimits,
                packedUserOp.preVerificationGas,
                packedUserOp.gasFees,
                keccak256(packedUserOp.paymasterAndData)
            )
        );

        bytes32 digest = userOpHash.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        packedUserOp.signature = signature;

        uint256 missingAccountFunds = 0;

        vm.prank(address(entryPoint));
        uint256 validationData = simpleAccount.validateUserOp(packedUserOp, userOpHash, missingAccountFunds);

        assertEq(validationData, simpleAccount.SIG_VALIDATION_SUCCESS());
    }

    function createAccount() public returns (SimpleAccount) {
        bytes memory data = abi.encodeWithSelector(simpleAccountImpl.initialize.selector, owner);

        vm.prank(owner);
        ERC1967Proxy simpleAccountProxy = new ERC1967Proxy(address(simpleAccountImpl), data);

        return SimpleAccount(payable(address(simpleAccountProxy)));
    }
}
