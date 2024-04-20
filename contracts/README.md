# ERC-4337: 계정 추상화

## 개요 (Abstract)

- 합의 계층 프로토콜을 변경하지 않고도 계정 추상화를 가능케 하는 제안
- 새로운 프로토콜 기능 또는 새로운 트랜잭션 유형을 도입하는 대신, `UserOperation`이라는 상위 계층 수도-트랜잭션 객체(higher-layer pseudo-transaction object)를 도입
- 사용자는 `UserOperation`을 생성하고 전용 멤풀에 전송
- `번들러(bundler)`라는 특별한 종류의 행위자는 사용자 작업 전용 멤풀에서 작업을 수집하고, 패키지화하여 특정 컨트랙트의 `handleOps` 함수를 호출
- 패키지화된 `UserOperation`들은 하나의 트랜잭션으로 처리되어 블록에 포함

## 동기 (Motivation)

- **계정 추상화의 주요 목표 달성(Achieve the key goal of account abstraction)**: EOA의 필요성을 제거하고 사용자들이 임의의 검증 로직이 포함된 스마트 컨트랙트 지갑을 사용할 수 있도록 합니다.
- **탈중앙화(Decentralization)**: 누구나 번들러가 될 수 있습니다.
- **이더리움 합의 계층 변경 회피(Do not require any Ethereum consensus changes)**
- **다른 사용 사례 지원(Try to support other use cases)**
  - 개인 정보 보호 애플리케이션
  - 원자적 다중 작업 (EIP-3074와 유사한 목표)
  - 트랜잭션 수수료를 ERC-20 토큰으로 지불하고 개발자가 사용자를 대신하여 수수료를 지불하도록 허용하며, [EIP-3074]와 유사한 후원 트랜잭션 사용 사례를 일반적으로 지원
  - 집계 서명 지원 (예: BLS)

## 명세 (Specification)

### 정의 (Definitions)

- **UserOperation**: 사용자를 대신하여 실행할 작업을 나타내는 트랜잭션 구조체. 기존 용어와 혼동을 피하기 위해 트랜잭션이라는 이름을 사용하지 않습니다.
  - 트랜잭션과 마찬가지로 'sender', 'to', 'calldata', 'maxFeePerGas', 'maxPriorityFee', 'signature', 'nonce'를 포함
  - 트랜잭션에는 없는 필드들도 일부 포함 (아래 참조)
  - 'signature' 필드의 사용은 이더리움 프로토콜에 의해 정해지지 않고 각 계정의 구현에 따라 달라집니다.
- **Sender**: 사용자 작업이 실행될 컨트랙트 계정의 주소
- **EntryPoint**: `UserOperation`의 번들을 실행하는 싱글톤 컨트랙트
- **Bundler**: `UserOperation`을 수집하고 EntryPoint.handleOps()를 호출하는 유효한 트랜잭션을 생성. 해당 트랜잭션은 모든 작업이 유효한 동안에만 블록에 포함될 수 있습니다.
- **Paymaster**: sender 대신 수수료를 지불하는 도우미 컨트랙트
- **Aggregator**: 서명 집계를 수행하는 도우미 컨트랙트

### UserOperation

합의 계층 변경을 피하기 위해 새로운 트랜잭션 유형을 도입하는 대신, 사용자들은 그들이 원하는 작업을 컨트랙트 계정이 수행할 수 있도록 `UserOperation` 구조체를 생성합니다.

| Field                           | Type      | Description                                                                   |
| ------------------------------- | --------- | ----------------------------------------------------------------------------- |
| `sender`                        | `address` | 작업을 실행하는 계정의 주소                                                   |
| `nonce`                         | `uint256` | 재생 공격을 방지하기 위한 파라미터                                            |
| `factory`                       | `address` | 컨트랙트 계정을 생성하는 팩토리, 계정이 생성되어 있지 않은 경우에만           |
| `factoryData`                   | `bytes`   | 팩토리 컨트랙트를 호출하는 데 사용할 데이터 (계정 팩토리가 존재하는 경우에만) |
| `callData`                      | `bytes`   | `sender`에 전달할 작업 데이터                                                 |
| `callGasLimit`                  | `uint256` | 작업 실행에 할당할 가스의 양                                                  |
| `verificationGasLimit`          | `uint256` | 검증 단계에 할당할 가스의 양                                                  |
| `preVerificationGas`            | `uint256` | bundler에게 지불할 여분의 가스                                                |
| `maxFeePerGas`                  | `uint256` | 가스당 최대 수수료 ([EIP-1559](./eip-1559.md) `max_fee_per_gas`와 유사)       |
| `maxPriorityFeePerGas`          | `uint256` | 가스당 최대 우선순위 수수료 (EIP-1559 `max_priority_fee_per_gas`와 유사)      |
| `paymaster`                     | `address` | paymaster 컨트랙트의 주소, (계정에서 수수료를 지불하는 경우, 비어 있음)       |
| `paymasterVerificationGasLimit` | `uint256` | paymaster 검증에 할당할 가스의 양                                             |
| `paymasterPostOpGasLimit`       | `uint256` | paymaster 후속 작업(post-op)에 할당할 가스의 양                               |
| `paymasterData`                 | `bytes`   | paymaster 컨트랙트를 호출하는 데 사용할 데이터 (paymaster가 명시된 경우만)    |
| `signature`                     | `bytes`   | 컨트랙트 계정 소유자의 서명                                                   |

1. 사용자들은 UserOperation 객체를 전용 사용자 작업 멤풀로 보냅니다.
2. 번들러라고 불리는 특별한 유형의 행위자들이 사용자 작업 멤풀을 감시하고, 여러 UserOperation 객체를 패키지화하여 하나의 번들 트랜잭션을 생성합니다.
3. 패키지화된 UserOperation들은 하나의 트랜잭션으로 EntryPoint 컨트랙트의 handleOps 호출을 통해 처리됩니다.

> 재생 공격(replay attack)을 방지하기 위해(크로스 체인 및 여러 EntryPoint 구현체 등에서), `signature`는 `chainid`와 `EntryPoint` 주소에 의존해야 합니다.

### PackedUserOperation

온체인 컨트랙트(EntryPoint 컨트랙트, Account 및 Paymaster)에 사용자 작업이 전달될 때, UserOperation 구조체의 패킹된 버전(PackedUserOperation)을 사용:

| Field                | Type      | Description                                                                       |
| -------------------- | --------- | --------------------------------------------------------------------------------- |
| `sender`             | `address` |                                                                                   |
| `nonce`              | `uint256` |                                                                                   |
| `initCode`           | `bytes`   | factory 주소와 factoryData를 연결한 데이터                                        |
| `callData`           | `bytes`   |                                                                                   |
| `accountGasLimits`   | `bytes32` | verificationGas (16 바이트)와 callGas (16 바이트)를 연결한 데이터 (32 바이트)     |
| `preVerificationGas` | `uint256` |                                                                                   |
| `gasFees`            | `bytes32` | maxPriorityFee (16 바이트)와 maxFeePerGas (16 바이트)를 연결한 데이터 (32 바이트) |
| `paymasterAndData`   | `bytes`   | paymaster와 관련된 필드를 연결한 데이터 (paymaster가 없는 경우 비어 있음)         |
| `signature`          | `bytes`   |                                                                                   |

### Account

스마트 컨트랙트 계정은 사용자가 EOA를 직접 사용하지 않고도 계정을 생성하고 사용할 수 있도록 해주는 계정 추상화 계층입니다. 계정은 다음과 같은 인터페이스를 구현해야 합니다:

```solidity
interface IAccount {
  function validateUserOp
      (PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
      external returns (uint256 validationData);
}
```

`userOpHash`는 서명을 제외한 userOp의 해시와 entryPoint 주소, 그리고 chainid의 해시(keccak256)입니다.

> keccak256(abi.encode(userOp.hash(), entryPoint, block.chainid));

`validateUserOp` 함수에서 계정은:

- 호출자가 신뢰하는 EntryPoint 컨트랙트인지 반드시 확인해야 합니다.
- 만약 계정이 서명 집계를 지원하지 않는다면, 반드시 서명이 userOpHash에 대한 유효한 서명인지 확인해야 하며, 서명이 일치하지 않을 경우 SIG_VALIDATION_FAILED를 반환해야 합니다. 다른 오류는 revert해야 합니다.
- 반드시 `missingAccountFunds` 이상의 금액을 `entryPoint`에 지불해야 합니다. (현재 계정의 예치금이 충분한 경우에는 0일 수 있음)
- 최소 금액보다 더 많이 지불할 수도 있습니다. 이는 향후 발생할 트랜잭션을 위해 사용될 수 있습니다. (withdrawTo를 사용하여 회수 가능)
- 함수의 반환값은 `authorizer`, `validUntil`, `validAfter`를 포함해야 합니다.
  - `authorizer`가 0이면 유효한 서명을 나타내며, 1이면 서명 검증 실패를 나타냅니다. 그 외의 경우는 서명 집계자(aggregator) 컨트랙트의 주소를 나타냅니다.
  - `validUntil`은 6바이트 타임스탬프 값이며, 0이면 "무제한"을 나타냅니다. UserOp은 이 시간까지만 유효합니다.
  - `validAfter`는 6바이트 타임스탬프입니다. UserOp은 이 시간 이후에만 유효합니다.

### EntryPoint

handleOps 함수를 통해 UserOperation을 처리하는 싱글톤 컨트랙트. 번들러로부터 패키지화된 UserOperation을 받아들이고 처리합니다.

```solidity
function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary);

function handleAggregatedOps(
    UserOpsPerAggregator[] calldata opsPerAggregator,
    address payable beneficiary
);

struct UserOpsPerAggregator {
    PackedUserOperation[] userOps;
    IAggregator aggregator;
    bytes signature;
}
```

### 부분 추상화된 논스 지원 (Semi-abstracted Nonce Support)

#### 기존의 Nonce 시스템

트랜잭션의 `nonce` 값은 연속적인 숫자로, 트랜잭션의 순서를 결정하여 중복이 발생하는 것을 방지하고, 트랜잭션이 블록에 포함되는 순서를 결정하는 데 사용됩니다.

또한, 이전에 사용된 nonce를 재사용한 트랜잭션은 블록체인에 포함될 수 없기 때문에 트랜잭션 해시의 고유성에 기여합니다.

#### 계정 추상화에 사용되는 Nonce 메커니즘

기존의 단일한 연속된 `nonce`를 요구하는 것은 사용자가 트랜잭션 순서와 재생 방지 로직을 사용자 정의하는 데 제한을 줄 수 있습니다.

계정 추상화를 위해, 기존의 `nonce` 시스템 대신, 단일한 `uint256` 타입의 nonce 값을 사용하면서도 이를 두 부분으로 나누어 사용할 수 있습니다:

- 192비트의 "key"
- 64비트의 "sequence"

이 값들은 체인상에서 EntryPoint 컨트랙트에 표현되며, 다음과 같은 메소드를 EntryPoint 인터페이스에 정의하여 이 값을 사용할 수 있습니다:

```solidity
function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
```

각 `key`에 대해 `sequence`는 EntryPoint에 의해 각 UserOperation에 대해 순차적이고 단조롭게 검증되고 증가합니다. 새로운 key는 언제든지 임의의 값으로 설정할 수 있습니다.

이 접근 방식은 프로토콜 수준에서 UserOperation의 해시 고유성을 보장하는 동시에, 지갑에서 192비트 "key" 필드를 사용하여 임의의 사용자 정의 로직을 구현할 수 있게 합니다.

### EntryPoint 컨트랙트의 기능 요구사항

- `handleOps` 함수는 서명 집계를 지원하지 않는 계정의 userOps를 처리할 수 있어야 합니다.
- `handleAggregatedOps` 함수는 여러 서명 집계기(aggregator)의 userOps를 일괄 처리할 수 있어야 하며, 집계기가 없는 요청도 처리할 수 있어야 합니다.
- `handleAggregatedOps` 함수는 `handleOps`와 동일한 로직을 사용하여 userOps를 처리하되, 올바른 집계기에 userOp를 전달하고, 모든 계정 검증을 실행하기 전에 반드시 각 집계기의 `validateSignatures` 함수를 호출하여 서명을 검증해야 합니다.

- `EntryPoint` 컨트랙트의 `handleOps` 함수는 반드시 **verification loop**와 **execution loop**를 포함하여 UserOperation을 처리해야 합니다. (우선 Paymaster가 없는 경우에 대한 설명)

#### Verification Loop

1. 컨트랙트 계정이 존재하지 않는 경우, initCode를 사용하여 컨트랙트 계정을 생성합니다. 계정이 존재하지 않고 initCode가 없는 경우, revert합니다.
2. 컨트랙트 계정이 지불해야 할 최대 가능 수수료를 계산합니다.
3. 컨트랙트 계정이 `EntryPoint`에 예치해야 하는 금액을 계산합니다.
4. 컨트랙트 계정의 `validateUserOp` 함수를 호출하여 UserOperation, UserOperation의 해시, 계정이 지불해야 할 금액을 전달합니다.
   - 컨트랙트 계정은 서명을 검증하고, 서명이 유효하면 예치금을 지불하고 `authorizer`, `validUntil`, `validAfter`를 반환합니다.
5. `EntryPoint`가 계정의 예치금이 충분한지 확인합니다. (이미 진행된 검증 작업에 대한 수수료 포함)

#### Execution Loop

1. `UserOperation`의 **callData**를 사용하여 컨트랙트 계정을 호출합니다.
   - 데이터를 파싱하는 방법은 계정의 구현에 따라 다를 수 있습니다.
   - 가능한 작업 흐름은 계정이 `execute` 함수를 가지고 있고, 이를 통해 작업을 실행하는 것입니다.
2. 작업을 실행하고 나면, 사전에 청구된 수수료에서 실제로 청구된 수수료를 뺀 나머지를 계정에 반환합니다.
   - `10%`의 `UNUSED_GAS_PENALTY_PERCENT` 패널티가 적용됩니다.
   - 패널티를 적용하는 이유는 사용자가 너무 많은 가스를 요청하여 다른 사용자들의 작업이 번들에 포함되지 못하도록 하는 것을 방지하기 위함입니다.
3. 모든 작업이 성공적으로 완료되면, `bundler`가 지정한 `beneficiary`에게 수거한 수수료를 지급합니다.

![UserOperation Flow](https://eips.ethereum.org/assets/eip-4337/bundle-seq.svg)

`UserOperation`을 받아들이기 전에 `bundler`는 RPC 메서드를 사용하여 `EntryPoint` 컨트랙트의 `simulateValidation` 함수를 로컬에서 호출하여 작업이 유효한지 먼저 확인해야 합니다. 유효하지 않은 작업은 반드시 드롭하여 멤풀에 포함시키지 않아야 합니다.

### Paymaster

`Paymaster`는 사용자의 수수료를 대납하는 데 사용하는 도우미 컨트랙트입니다. 구체적으로, 애플리케이션 개발자가 사용자를 대신하여 수수료를 지불할 수 있으며, 지불 방식은 네이티브 토큰이 아닌 ERC-20 토큰을 사용할 수도 있습니다.

`Paymaster`는 다음과 같은 인터페이스를 구현해야 합니다:

```solidity
function validatePaymasterUserOp
    (PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
    external returns (bytes memory context, uint256 validationData);

function postOp
    (PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
    external;

enum PostOpMode {
    opSucceeded, // user op succeeded
    opReverted, // user op reverted. still has to pay for gas.
    postOpReverted // Regardless of the UserOp call status, the postOp reverted, and caused both executions to revert.
}
```

UserOp의 `paymasterAndData` 필드가 비어 있지 않은 경우, `EntryPoint` 컨트랙트는 `Paymaster` 컨트랙트는 UserOp를 처리하기 위한 다른 방법을 사용해야 합니다.

#### Paymaster를 사용하는 경우의 동작 방식

1. `validateUserOp` 함수를 호출하는 과정은 동일합니다. 차이가 있는 부분은 UserOp에 `paymaster`가 지정되어 있기 때문에 `EntryPoint`는 컨트랙트 계정으로부터 수수료를 송금받지 않습니다.
2. 대신 `EntryPoint` 컨트랙트는 `Paymaster` 컨트랙트의 `validatePaymasterUserOp` 함수를 호출합니다.
   - `validatePaymasterUserOp` 함수는 `Paymaster` 컨트랙트가 사용자의 수수료를 지불할 것인지 여부를 확인합니다.
3. `Paymaster`의 `validatePaymasterUserOp` 함수는 `context`와 `validationData`를 반환합니다.
   - `context`는 `postOp` 함수를 호출할 때 사용됩니다.
   - `validationData`는 `validateUserOperation` 함수의 반환값과 동일한 역할을 합니다.
4. `EntryPoint` 컨트랙트는 **Execution Loop**를 실행하고 마지막에 `Paymaster`의 `postOp` 함수를 호출합니다.
   - `postOp` 함수는 `mode`, `context`, `actualGasCost`, `actualUserOpFeePerGas`를 인자로 받습니다.
   - `mode`는 `opSucceeded`, `opReverted`, `postOpReverted` 중 하나입니다.
   - `actualGasCost`는 실제로 소비된 가스량을 나타냅니다.
   - `actualUserOpFeePerGas`는 실제로 청구된 사용자 수수료를 나타냅니다.
5. `postOp`로 호출된 `Paymaster`는 사용자의 수수료를 지불하고, `mode`에 따라 다른 작업을 수행합니다.

![Paymaster Flow](https://eips.ethereum.org/assets/eip-4337/bundle-seq-pm.svg)

#### 악의적인 Paymaster 방지책

`Paymaster`는 사용자의 수수료를 지불하는 도우미 컨트랙트이지만, 악의적으로 동작하서 DoS 공격을 수행할 수 있습니다.

이를 방지하기 위해

1. **명성(reputation)** 시스템을 도입하여, 사용자 또는 번들러가 신뢰할 수 있는 `Paymaster`를 선택할 수 있도록 합니다.
2. 스토리지 사용을 제한하거나 `EntryPoint`에 자금을 스테이킹하도록 요구하여, 악의적인 동작을 방지합니다.

`EntryPoint` 컨트랙트는 다음과 같은 API를 구현하여 `Paymaster`가 스테이킹을 통해 스토리지 제약없이 유연하게 동작할 수 있도록 만들 수 있습니다:

```solidity
// add a stake to the calling entity
function addStake(uint32 _unstakeDelaySec) external payable

// unlock the stake (must wait unstakeDelay before can withdraw)
function unlockStake() external

// withdraw the unlocked stake
function withdrawStake(address payable withdrawAddress) external
```

### 서명 집계자 (Signature Aggregator)

서명 집계자는 다음과 같은 인터페이스를 구현해야 합니다:

```solidity
interface IAggregator {

  function validateUserOpSignature(PackedUserOperation calldata userOp)
  external view returns (bytes memory sigForUserOp);

  function aggregateSignatures(PackedUserOperation[] calldata userOps) external view returns (bytes memory aggregatesSignature);

  function validateSignatures(PackedUserOperation[] calldata userOps, bytes calldata signature) view external;
}
```

- 스마트 계정은 `validateUserOp` 함수의 반환값에 서명 집계자의 주소를 포함함으로써 서명 집계를 지원함을 나타냅니다.
- `simulationValidation` 함수가 실행되는 동안, 이 서명 집계자(반환된 값)는 `aggregatorInfo` 구조체의 일부로 번들러에게 반환됩니다.
- 번들러는 최우선 순위로 서명 집계자를 수락해야 합니다. (서명 집계자가 적절한 수준의 보증금을 제공해야 하고, 번들러는 서명 집계자가 throttle 또는 banned 상태가 아닌지 확인해야 합니다.)
- UserOp를 번들러가 처리하기 전에, 번들러는 `validateUserOpSignature` 함수를 호출하여 UserOp의 서명을 검증해야 합니다. 이 함수는 UserOp의 대체 서명을 반환(보통 빈 값)하며, 번들러는 번들링 중에 이 서명을 사용해야 합니다.
- 번들러는 위에서 반환된 대체 서명을 사용하여 두 번째로 스마트 계정의 `validateUserOp` 함수를 호출하며, 이전에 반환된 값과 동일한 값이 반환되는지 확인해야 합니다.
- **aggregateSignatures** 함수는 모든 UserOp 서명을 하나의 값으로 집계해야 합니다.
- 위의 메서드들은 번들러를 위한 도우미 메서드입니다. 번들러는 동일한 검증 및 집계 로직을 수행하기 위해 네이티브 라이브러리를 사용할 수 있습니다.
- **validateSignatures** 함수는 배열의 모든 UserOperation에 대한 집계 서명이 일치하는지 검증해야 합니다. 일치하지 않으면 revert해야 합니다. 이 메서드는 on-chain에서 handleOps()에 의해 호출됩니다.

### 시뮬레이션 (Simulation)

#### 시뮬레이션의 필요성에 대한 근거 (Rationale)

UserOperation을 멤풀에 추가하기 위해 (그리고나서 번들에 추가하기 위해) 우리는 오프체인에서 해당 작업이 유효하고, 자체적으로 실행 비용을 지불할 수 있는지 확인해야 합니다. 또한 온체인에서 실행될 때도 동일한 조건이 유지되는지 확인해야 합니다. 이를 위해, UserOperation은 시뮬레이션 단계와 실행 단계 사이에 변경되는 정보(예: 블록 시간, 블록 번호, 블록 해시 등)에는 접근할 수 없어야 합니다. 또한 UserOperation은 sender 주소와 관련된 데이터에만 접근할 수 있어야 하며, 여러 개의 UserOperation이 동일한 스토리지에 접근하지 않도록 해야 합니다. 이렇게 함으로써 하나의 상태 변경으로 많은 UserOperation을 무효화되는 문제를 방지할 수 있습니다. 계정과 상호 작용하는 3개의 특별한 컨트랙트는 다음과 같습니다. 계정을 배포하는 팩토리 (initCode), 가스 비용을 지불할 수 있는 페이마스터, 그리고 서명 집계기; 각 컨트랙트 또한 스토리지 접근이 제한되어, UserOperation 검증이 고립되도록 합니다.

#### 시뮬레이션 사양 (Specification)

`UserOperation`을 시뮬레이션하기 위해, 클라이언트는 `simulateValidation(userop)`을 호출합니다.

EntryPoint 자체는 시뮬레이션 메서드를 구현하지 않았습니다. 대신 시뮬레이션이 필요한 경우, 번들러는 EntryPoint를 시뮬레이션 메소드로 확장하는 EntryPointSimulations 코드를 제공해야 합니다.

시뮬레이션의 핵심 메서드는 다음과 같습니다:

```solidity
struct ValidationResult {
    ReturnInfo returnInfo;
    StakeInfo senderInfo;
    StakeInfo factoryInfo;
    StakeInfo paymasterInfo;
    AggregatorStakeInfo aggregatorInfo;
}

function simulateValidation(PackedUserOperation calldata userOp)
external returns (ValidationResult memory);

struct ReturnInfo {
    uint256 preOpGas;
    uint256 prefund;
    uint256 accountValidationData;
    uint256 paymasterValidationData;
    bytes paymasterContext;
}

struct AggregatorStakeInfo {
    address aggregator;
    StakeInfo stakeInfo;
}

struct StakeInfo {
  uint256 stake;
  uint256 unstakeDelaySec;
}
```

이 메서드는 `ValidationResult`를 반환하거나 유효성 검사 실패 시 revert합니다. 노드는 시뮬레이션이 실패할 경우 UserOperation을 드롭해야 합니다(서명 검증 실패 또는 revert되는 경우).

시뮬레이션된 호출은 다음을 호출하여 전체 검증을 수행합니다:

1. 계정이 존재하지 않는 경우, `initCode`를 사용하여 계정을 생성합니다.
2. 계정의 `validateUserOp` 함수를 호출합니다.
3. paymaster가 지정된 경우, paymaster의 `validatePaymasterUserOp` 함수를 호출합니다.

`simulateValidation`은 계정의 `validateUserOp` 및 paymaster의 `validatePaymasterUserOp`에서 반환된 반환 값(validationData)을 검증해야 합니다. 계정에서 반환된 값에는 집계기(aggregator)의 주소가 포함될 수 있습니다. 페이마스터에서는 0 또는 SIG_VALIDATION_FAILED이 반환되어야 하며 주소는 반환되어서는 안됩니다. 반환 값에는 "validAfter" 및 "validUntil" 타임스탬프가 포함될 수 있습니다. 이는 UserOperation이 온체인상에서 유효한 시간 범위를 나타냅니다. 노드는 계정이나 페이마스터에 의해 너무 빠르게 만료(다음 블록 생성에 포함되지 못할 경우)되는 UserOperation을 드롭할 수 있습니다. ValidationResult에 sigFail이 포함되어 있는 경우, 클라이언트는 UserOperation을 드롭해야 합니다.

번들러에 대한 DoS 공격을 방지하기 위해, 그들은 위의 검증 방법이 검증 규칙을 통과하도록 해야 하며, 이는 그들의 opcode 및 스토리지 사용을 제한합니다. 전체 절차는 [ERC-7562](https://eips.ethereum.org/EIPS/eip-7562)를 참조하세요.

### 번들링 (Bundling)

번들링은 노드/번들러가 여러 UserOperation을 수집하고 하나의 트랜잭션을 생성하여 온체인에 제출하는 과정입니다.

번들러는 다음과 같은 규칙을 준수해야 합니다:

- 번들에 포함된 다른 계정(sender)의 주소에 접근하는 UserOperation은 제외해야 합니다.
- 번들에 포함된 다른 UserOperation에 의해 생성된 주소(예: 팩토리를 통해 생성된 계정의 주소)에 접근하는 UserOperation은 제외해야 합니다.
- 번들에서 사용된 각 페이마스터의 잔액을 추적하고, 해당 페이마스터를 사용하는 모든 UserOperation에 대해 충분한 예치금이 있는지 확인해야 합니다.
- UserOperation을 서명 집계자에 따라 정렬하여 각 집계자별 UserOperation 목록(UserOps-per-aggregator)을 생성해야 합니다.
- 각 집계자별 UserOperation 목록을 사용하여 집계 서명을 생성해야 합니다. 그리고 UserOps를 업데이트해야 합니다.

번들을 생성한 뒤, 트랜잭션을 블록에 포함하기 전에 다음 단계를 수행해야 합니다:

- 가능한 최대 가스량으로 `debug_traceCall`을 실행하여 opcode 및 스토리지 액세스에 대한 검증 규칙을 강제하고, `handleOps` 배치 트랜잭션을 확인하며, 소비된 가스를 측정하여 실제 트랜잭션 실행에 사용해야 합니다.
- 호출이 revert된 경우, 번들러는 해당 호출이 revert되게 만든 엔티티를 찾기 위해 EntryPoint에 의해 호출된 마지막 엔티티를 식별해야 합니다.
- 만약 검증 콘텍스트 규칙이 위배되었다면, 번들러는 이를 `UserOperation`이 revert된 것과 동일하게 처리해야 합니다.
- 문제가 발생한 UserOperation을 번들과 멤풀에서 제거해야 합니다.
- 오류가 팩토리 또는 페이마스터에 의해 발생했고, UserOp의 sender가 스테이크된 엔티티가 아닌 경우, 해당 팩토리 또는 페이마스터에 대해 "밴" 처리를 해야 합니다.
- 오류가 팩토리 또는 페이마스터에 의해 발생했고, UserOp의 sender가 스테이크된 엔티티인 경우, 팩토리 또는 페이마스터를 멤풀에서 밴하지 않고, 대신 staked sender 엔티티에 대해 "밴" 처리를 해야 합니다.
- 이 과정을 반복하여 `debug_traceCall`이 성공할 때까지 계속해야 합니다.

`handleOps`의 검증 전체에 대해 개별 UserOperation과 동일한 opcode 및 프리컴파일 금지 규칙 및 스토리지 액세스 규칙이 강제되어야 합니다. 그렇지 않으면 공격자가 금지된 opcodes를 사용하여 온체인에서 `FailedOp`로 트랜잭션이 revert되도록 유도할 수 있습니다.

### 에러 코드 (Error Codes)

검증을 수행하는 동안, EntryPoint는 실패 시 revert되어야 합니다. 시뮬레이션 중, 호출자(번들러)는 어떤 엔티티(팩토리, 계정 또는 페이마스터)가 실패를 발생시켰는지 결정할 수 있어야 합니다. 이를 위해, EntryPoint에 의해 마지막으로 호출된 엔티티를 식별하는 방법이 필요합니다.

- 오류 진단을 위해 EntryPoint는 명시적인 FailedOp() 또는 FailedOpWithRevert() 오류로만 실패해야 합니다.
- 오류 메시지는 이벤트 코드, AA##로 시작합니다.
- “AA1”로 시작하는 이벤트 코드는 계정 생성 중 오류를 나타냅니다.
- “AA2”로 시작하는 이벤트 코드는 계정 검증(validateUserOp) 중 오류를 나타냅니다.
- “AA3”로 시작하는 이벤트 코드는 페이마스터 검증(validatePaymasterUserOp) 중 오류를 나타냅니다.

## 설계에 대한 이론적 근거 (Rationale)

계정 추상화 시스템을 순수하게 스마트 계약 지갑 기반으로 구현하는 데 있어 주요 도전 과제 중 하나는 DoS(서비스 거부) 공격 방지입니다: 블록 빌더가 작업을 포함할 때, 전체 작업을 실행하지 않고도 해당 작업이 실제로 수수료를 지불할 것인지 확신할 수 있을까요? 블록 빌더가 전체 작업을 실행하도록 요구하는 것은 DoS 공격 경로를 열어줍니다. 공격자는 수수료를 지불하는 척 하고 긴 실행 후 마지막 순간에 revert되는 작업들을 쉽게 보낼 수 있기 때문입니다. 마찬가지로 공격자들이 저렴한 비용으로 멤풀을 막히게 하는 것을 방지하기 위해, P2P 네트워크의 노드는 작업을 전달하기 전에 작업이 수수료를 지불하는지 우선 확인해야 합니다.

이런한 문제를 해결하기 위한 첫 번째 단계는 검증(validate)과 실행(execute) 사이의 명확한 분리입니다. 이 제안에서는 계정이 UserOperation을 입력으로 받고 서명을 검증하고 수수료를 지불하는 validateUserOp 메소드를 갖추고 있을 것으로 기대합니다. 이 메소드가 검증에 성공하면 실행 단계가 진행됩니다.

진입점 기반(entry point-based) 접근 방식은 검증과 실행 사이의 명확한 분리를 가능케 하며, 계정의 로직을 단순하게 유지합니다. 이는 검증이 성공한 후에만(그리고 UserOp가 지불할 수 있을 때) 실행이 이루어지며 수수료 지불을 보장한다는 간단한 규칙을 강제합니다.

### 검증 규칙의 이론적 근거 (Rationale)

다음 단계는 유효해 보이지만 결국에는 revert되어 번들에 포함된 다른 UserOperation이 처리되는 것을 방해하는 DoS 공격으로부터 번들러를 보호하는 것입니다.

검증에 실패하는 두 유형의 UserOperation이 있습니다:

- 초기 검증에 성공하고 멤풀에 받아들여지지만, 블록에 포함하려고 할 때 환경 상태(block number, block timestamp 등)에 의존하여 나중에 실패하는 UserOperation.
- 독립적으로 확인할 때는 유효하지만, 번들에 포함될 때 다른 UserOperation에 의해 무효화되는 UserOperation. 이러한 부정 작업을 방지하기 위해, 번들러는 검증 함수의 제약 조건을 따라야 합니다.

### 명성 시스템의 이론적 근거 (Rationale)

UserOperation의 스토리지 접근 규칙은 UserOperation이 서로 간섭하지 않는 것을 보장합니다. 그러나 "글로벌" 엔티티 - 페이마스터, 팩토리 및 집합기는 여러 UserOperation에 의해 접근되며, 따라서 이전에 유효했던 여러 UserOperation을 무효화할 수 있습니다.

남용을 방지하기 위해, 멤풀에서 UserOperation의 대량 무효화를 유발하는 엔티티를 완전히 금지하거나 제한합니다. 이러한 엔티티로부터의 "sybil-attack"을 방지하기 위해, 시스템에 자금을 스테이킹하도록 요구하여 DoS 공격을 매우 비싸게 만듭니다. 이 보증금은 절대로 공제되지 않으며, 일정 시간이 지난 후 언제든지 인출할 수 있습니다.

스테이킹한 엔티티는 더 많은 메모리를 사용할 수 있으며, 이는 번들러가 더 많은 작업을 처리할 수 있게 합니다.

스테이킹에 필요한 값은 체인상에서 강제되지 않고 각 노드가 트랜잭션을 시뮬레이션하는 동안 특정하게 적용됩니다.

### 페이마스터

페이마스터 컨트랙트는 트랜잭션의 sender는 아니지만, 트랜잭션 수수료를 지불함으로써 가스의 추상화를 제공합니다.

페이마스터의 아키텍처는 "선결제(pre-charge) 및 이후 환불(refund)" 모델을 따릅니다. 예를 들어, 토큰 페이마스터는 사용자에게 트랜잭션의 최대 가능한 가격을 선결제하고, 이후 초과분을 환불할 수 있습니다.

### 최초 계정 생성 (First-time account creation)

이 제안의 중요한 설계 목표는 EOA의 주요 속성을 복제함으로써 사용자가 자신의 지갑을 생성하기 위해 특정한 작업을 수행하거나 기존 사용자에 의존하지 않도록 하는 것입니다. 즉, 사용자는 지역적으로 주소를 생성하고 즉시 자금을 받기 시작할 수 있습니다.

지갑 생성은 "팩토리" 컨트랙트를 통해 이루어지며, 지갑에 따라 다른 데이터가 사용됩니다. 팩토리는 CREATE가 아닌 CREATE2를 사용하여 지갑을 생성합니다. 이는 지갑의 생성 순서가 생성된 주소에 영향을 미치지 않도록 하기 위함입니다. initCode 필드(길이가 0이 아닌 경우)는 20바이트 주소로 파싱된 뒤, 해당 주소로 전달할 "calldata"가 뒤따릅니다. 이 메소드 호출은 지갑을 생성하고 그 주소를 반환할 것으로 예상됩니다. 팩토리가 CREATE2 또는 다른 결정적 방법을 사용하여 지갑을 생성하는 경우, 이미 지갑이 생성되었더라도 지갑 주소를 반환할 것으로 예상됩니다. 이는 클라이언트가 지갑이 이미 배포되었는지 알지 못하는 상태에서 entryPoint.getSenderAddress()를 시뮬레이션 호출함으로써 주소를 쉽게 조회할 수 있도록 하기 위함입니다. initCode가 지정된 경우, sender 주소가 기존 계약을 가리키거나 initCode 호출 후에도 sender 주소가 여전히 존재하지 않는 경우, 작업은 중단됩니다. initCode는 entryPoint에서 직접 호출되어서는 안 되며, 다른 주소에서 호출되어야 합니다. 이 팩토리 메소드에 의해 생성된 계약은 UserOp의 서명을 검증하기 위해 validateUserOp 호출을 수용해야 합니다. 보안상의 이유로, 생성된 계약 주소는 초기 서명에 따라 달라져야 합니다. 이렇게 하면 누군가 그 주소에서 지갑을 생성할 수 있더라도 다른 자격 증명을 설정하여 제어할 수 없습니다. 팩토리가 글로벌 스토리지에 접근하는 경우 스테이킹이 필요합니다.

참고: 지갑이 생성되기 전 "가설적" 주소를 결정하기 위해서는 entryPoint.getSenderAddress()에 대해 정적 호출을 수행해야 합니다.

### 엔트리 포인트 업그레이드 (EntryPoint upgrading)

계정은 가스 효율성을 높이고 계정 업그레이드를 허용하기 위해 DELEGATECALL을 통해 실행되도록 권장됩니다. 계정 코드는 가스 효율성을 위해 코드 내에 진입점을 하드코딩할 것으로 예상됩니다.

새로운 기능을 추가하거나 가스 효율성을 개선하거나 중요한 보안 버그를 수정하기 위해 새로운 진입점이 도입되는 경우, 사용자는 자체 호출을 통해 계정의 코드 주소를 새로운 새로운 진입점을 가리키는 코드 주소로 교체할 수 있습니다. 업그레이드 과정 중에는 두 개의 멤풀이 병렬로 운영될 것으로 예상됩니다.

### RPC 메서드 (eth namespace)

생략 🥷

## 하위 호환성 (Backwards Compatibility)

이 제안은 합의 계층을 변경하지 않으므로, 이더리움 전체에 대한 하위 호환성 문제는 없습니다. 그러나 불행히도 이는 `validateUserOp` 함수를 가지지 않는 이전 ERC-4337 계정과 쉽게 호환되지 않습니다. 계정에 신뢰할 수 있는 작업 제출자를 인증하는 함수가 있다면, 검증 로직을 래퍼로 다시 구현하고 이를 원래 계정의 신뢰할 수 있는 작업 제출자로 설정함으로써 ERC-4337 호환 계정을 생성하여 이 문제를 해결할 수 있습니다.

## Reference Implementation

See https://github.com/eth-infinitism/account-abstraction/tree/main/contracts

## 보안 고려사항 (Security Considerations)

엔트리 포인트 컨트랙트는 모든 ERC4337 계정의 중심 신뢰 지점으로 작용하므로 매우 엄격하게 감사를 받아야 하며 공식적으로 검증이 되어야 합니다. 전체적으로, 이 아키텍처는 각 계정이 수행해야 하는 작업을 줄이므로 생태계에 대한 감사 및 공식 검증 부담을 줄입니다. 그러나 이는 결국 엔트리 포인트 컨트랙트에 보안 위험을 집중시키는 것을 의미합니다.

검증은 두 가지 주요 위험을 방지해야 합니다:

- 임의의 탈취에 대한 안전성: 진입점은 특정 계정에 대한 validateUserOp이 통과한 경우에만 일반 호출을 수행해야 합니다.
- 수수료 소진에 대한 안전성: 진입점이 validateUserOp을 호출하고 통과하면, op.calldata와 동일한 calldata를 사용하여 일반 호출을 수행해야 합니다.
