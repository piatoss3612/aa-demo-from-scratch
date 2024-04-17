// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {SimpleEntryPoint} from "../src/SimpleEntryPoint.sol";
import {SimpleAccountFactory} from "../src/SimpleAccountFactory.sol";
import {SimpleAccount} from "../src/SimpleAccount.sol";
import {SenderCreator} from "account-abstraction/core/SenderCreator.sol";

contract GenerateArtifactsScript is Script {
    function run() public {
        SimpleEntryPoint entryPoint = new SimpleEntryPoint();
        SenderCreator senderCreator = entryPoint.getSenderCreator();
        SimpleAccountFactory factory = new SimpleAccountFactory(entryPoint);
        SimpleAccount impl = factory.accountImplementation();

        string memory entryPointObject = "EntryPoint";
        string memory senderCreatorObject = "SenderCreator";
        string memory factoryObject = "SimpleAccountFactory";
        string memory implObject = "SimpleAccount";

        saveJson(entryPointObject, address(entryPoint));
        saveJson(senderCreatorObject, address(senderCreator));
        saveJson(factoryObject, address(factory));
        saveJson(implObject, address(impl));
    }

    function saveJson(string memory key, address addr) internal {
        string memory addrStr = vm.serializeAddress(key, "address", addr);
        string memory bytecode = vm.serializeBytes(key, "code", addr.code);

        string memory fileName = string(abi.encodePacked("./artifacts/", key, ".json"));

        vm.writeJson(addrStr, fileName);
        vm.writeJson(bytecode, fileName);
    }
}
