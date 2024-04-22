// Sources flattened with hardhat v2.17.3 https://hardhat.org

// SPDX-License-Identifier: GPL-3.0 AND LGPL-3.0-only

// File contracts/interfaces/ISmartAccountProxy.sol

// Original license: SPDX_License_Identifier: GPL-3.0
pragma solidity ^0.8.12;

/**
 * A wrapper factory contract to deploy SmartAccount as an Account-Abstraction wallet contract.
 */
interface ISmartAccountProxy {
    function masterCopy() external view returns (address);
}


// File contracts/wallet/v2/SmartAccountProxyV2.sol

// Original license: SPDX_License_Identifier: LGPL-3.0-only
pragma solidity ^0.8.12;

/// @title SmartAccountProxy - Generic proxy contract allows to execute all transactions applying the code of a master contract.
contract SmartAccountProxyV2 is ISmartAccountProxy {
    // singleton always needs to be first declared variable, to ensure that it is at the same location in the contracts to which calls are delegated.
    // To reduce deployment costs this variable is internal and needs to be retrieved via `getStorageAt`
    address internal singleton;

    /// @dev Constructor function sets address of singleton contract.
    /// @param _singleton Singleton address.
    function initialize(address _singleton, bytes memory _initdata) external {
        require(singleton == address(0), "Initialized already");
        require(_singleton != address(0), "Invalid singleton address provided");
        singleton = _singleton;

        (address creator, bytes memory params) = abi.decode(_initdata,(address, bytes));

        (bool success, bytes memory returnData) = _singleton.delegatecall(
            abi.encodeWithSignature("initialize(address,bytes)", creator, params)
        );
        require(success, string(returnData));
    }

    function masterCopy() external view returns (address) {
        return singleton;
    }

    /// @dev Fallback function forwards all transactions and returns all received return data.
    fallback() external payable {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let _singleton := and(
                sload(0),
                0xffffffffffffffffffffffffffffffffffffffff
            )
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(
                gas(),
                _singleton,
                0,
                calldatasize(),
                0,
                0
            )
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}
