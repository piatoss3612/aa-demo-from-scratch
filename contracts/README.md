# ERC-4337: 계정 추상화

## 개요 (Abstract)

- 합의 계층 프로토콜을 변경하지 않고도 계정 추상화를 가능케 하는 제안
- 새로운 프로토콜 기능 또는 새로운 트랜잭션 유형을 도입하는 대신, `UserOperation`이라는 상위 계층 수도-트랜잭션 객체(higher-layer pseudo-transaction object)를 도입
- 사용자는 `UserOperation`을 생성하고 이를 위한 전용 멤풀에 전송
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
