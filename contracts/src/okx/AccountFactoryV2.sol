// Sources flattened with hardhat v2.17.3 https://hardhat.org

// SPDX-License-Identifier: GPL-3.0 AND LGPL-3.0-only AND MIT

// File @openzeppelin/contracts/utils/Create2.sol@v4.9.3

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/Create2.sol)

pragma solidity ^0.8.0;

/**
 * @dev Helper to make usage of the `CREATE2` EVM opcode easier and safer.
 * `CREATE2` can be used to compute in advance the address where a smart
 * contract will be deployed, which allows for interesting new mechanisms known
 * as 'counterfactual interactions'.
 *
 * See the https://eips.ethereum.org/EIPS/eip-1014#motivation[EIP] for more
 * information.
 */
library Create2 {
    /**
     * @dev Deploys a contract using `CREATE2`. The address where the contract
     * will be deployed can be known in advance via {computeAddress}.
     *
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     *
     * - `bytecode` must not be empty.
     * - `salt` must have not been used for `bytecode` already.
     * - the factory must have a balance of at least `amount`.
     * - if `amount` is non-zero, `bytecode` must have a `payable` constructor.
     */
    function deploy(uint256 amount, bytes32 salt, bytes memory bytecode) internal returns (address addr) {
        require(address(this).balance >= amount, "Create2: insufficient balance");
        require(bytecode.length != 0, "Create2: bytecode length is zero");
        /// @solidity memory-safe-assembly
        assembly {
            addr := create2(amount, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Create2: Failed on deploy");
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy}. Any change in the
     * `bytecodeHash` or `salt` will result in a new destination address.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) internal view returns (address) {
        return computeAddress(salt, bytecodeHash, address(this));
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy} from a contract located at
     * `deployer`. If `deployer` is this contract's address, returns the same value as {computeAddress}.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer) internal pure returns (address addr) {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40) // Get free memory pointer

            // |                   | ↓ ptr ...  ↓ ptr + 0x0B (start) ...  ↓ ptr + 0x20 ...  ↓ ptr + 0x40 ...   |
            // |-------------------|---------------------------------------------------------------------------|
            // | bytecodeHash      |                                                        CCCCCCCCCCCCC...CC |
            // | salt              |                                      BBBBBBBBBBBBB...BB                   |
            // | deployer          | 000000...0000AAAAAAAAAAAAAAAAAAA...AA                                     |
            // | 0xFF              |            FF                                                             |
            // |-------------------|---------------------------------------------------------------------------|
            // | memory            | 000000...00FFAAAAAAAAAAAAAAAAAAA...AABBBBBBBBBBBBB...BBCCCCCCCCCCCCC...CC |
            // | keccak(start, 85) |            ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑ |

            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer) // Right-aligned with 12 preceding garbage bytes
            let start := add(ptr, 0x0b) // The hashed data starts at the final garbage byte which we will set to 0xff
            mstore8(start, 0xff)
            addr := keccak256(start, 85)
        }
    }
}


// File contracts/wallet/v2/AccountFactoryStorage.sol

// Original license: SPDX_License_Identifier: LGPL-3.0-only
pragma solidity ^0.8.12;

contract AccountFactoryStorageBase {
    address public implementation; // keep it the 1st slot
    address public owner;     // keep it the 2nd slot
    uint8   public initialized; // for initialize method.

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "OnlyOwner allowed");
        _;
    }
    
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract AccountFactoryStorage is AccountFactoryStorageBase {
    // SmartAccount template => bool, save the 
    mapping(address => bool) public safeSingleton;
    // wallet address => bool,  save accounts created by this Factory.
    // mapping(address => bool) public walletWhiteList;
    

    // NOTICE: add new storage variables below
}


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


// File contracts/wallet/v2/AccountFactoryV2.sol

// Original license: SPDX_License_Identifier: GPL-3.0
pragma solidity ^0.8.12;



/**
 * A wrapper factory contract to deploy SmartAccount as an Account-Abstraction wallet contract.
 */
contract AccountFactoryV2 is AccountFactoryStorage {
    event ProxyCreation(SmartAccountProxyV2 proxy, address singleton);
    event SafeSingletonSet(address safeSingleton, bool value);

    function initialize(address walletTemplate) public {
        require(initialized == 0, "only initialize once");
        initialized = 1;
        safeSingleton[walletTemplate] = true;
        emit SafeSingletonSet(walletTemplate, true);
    }

    function setSafeSingleton(
        address _safeSingleton,
        bool value
    ) public onlyOwner {
        safeSingleton[_safeSingleton] = value;
        emit SafeSingletonSet(_safeSingleton, value);
    }

    /// @dev Allows to retrieve the runtime code of a deployed Proxy. This can be used to check that the expected Proxy was deployed.
    function proxyRuntimeCode() public pure returns (bytes memory) {
        return type(SmartAccountProxyV2).runtimeCode;
    }

    /// @dev Allows to retrieve the creation code used for the Proxy deployment. With this it is easily possible to calculate predicted address.
    function proxyCreationCode() public pure returns (bytes memory) {
        return type(SmartAccountProxyV2).creationCode;
    }

    /// @dev Allows to create new proxy contact using CREATE2 but it doesn't run the initializer.
    ///      This method is only meant as an utility to be called from other methods
    /// @param initializer Payload for message call sent to new proxy contract.
    /// @param saltNonce Nonce that will be used to generate the salt to calculate the address of the new proxy contract.
    function deployProxyWithNonce(
        address, /* keep for external apis */
        bytes memory initializer,
        uint256 saltNonce
    ) internal returns (SmartAccountProxyV2 proxy) {
        // If the initializer changes the proxy address should change too. Hashing the initializer data is cheaper than just concatinating it
        address creator = abi.decode(initializer, (address));

        bytes32 salt = keccak256(
            abi.encodePacked(creator, saltNonce)
        );

        bytes memory deploymentData = abi.encodePacked(
            type(SmartAccountProxyV2).creationCode
        );
        // solhint-disable-next-line no-inline-assembly
        assembly {
            proxy := create2(
                0x0,
                add(0x20, deploymentData),
                mload(deploymentData),
                salt
            )
        }
        require(address(proxy) != address(0), "Create2 call failed");
    }

    /// @dev Allows to create new proxy contact and execute a message call to the new proxy within one transaction.
    /// @param _singleton Address of singleton contract.
    /// @param initializer Payload for message call sent to new proxy contract.
    /// @param saltNonce Nonce that will be used to generate the salt to calculate the address of the new proxy contract.
    function createProxyWithNonce(
        address _singleton,
        bytes memory initializer,
        uint256 saltNonce
    ) internal returns (SmartAccountProxyV2 proxy) {
        proxy = deployProxyWithNonce(_singleton, initializer, saltNonce);

        if (initializer.length > 0) {
            // solhint-disable-next-line no-inline-assembly
            bytes memory initdata = abi.encodeWithSelector(
                SmartAccountProxyV2.initialize.selector,
                _singleton,
                initializer
            );

            assembly {
                if eq(
                    call(
                        gas(),
                        proxy,
                        0,
                        add(initdata, 0x20),
                        mload(initdata),
                        0,
                        0
                    ),
                    0
                ) {
                    revert(0, 0)
                }
            }
        }

        emit ProxyCreation(proxy, _singleton);
    }

    function createAccount(
        address _safeSingleton,
        bytes memory initializer,
        uint256 salt
    ) public returns (address) {
        require(safeSingleton[_safeSingleton], "Invalid singleton");

        address addr = getAddress(_safeSingleton, initializer, salt);
        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return addr;
        }

        return address(createProxyWithNonce(_safeSingleton, initializer, salt));
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     * (uses the same "create2 signature" used by SmartAccountProxyFactory.createProxyWithNonce)
     */
    function getAddress(
        address, /* useless value, keep for external apis */
        bytes memory initializer,
        uint256 salt
    ) public view returns (address) {
        //copied from deployProxyWithNonce
        // omit another parameters while create wallet address
        address creator = abi.decode(initializer, (address));

        bytes32 salt2 = keccak256(
            abi.encodePacked(creator, salt)
        );
        bytes memory deploymentData = abi.encodePacked(
            type(SmartAccountProxyV2).creationCode
        );
        return
            Create2.computeAddress(
                bytes32(salt2),
                keccak256(deploymentData),
                address(this)
            );
    }
}
