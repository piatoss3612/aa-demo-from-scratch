// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {SenderCreator} from "account-abstraction/core/SenderCreator.sol";

contract SimpleEntryPoint is EntryPoint {
    function getSenderCreator() external view returns (SenderCreator) {
        return senderCreator();
    }
}
