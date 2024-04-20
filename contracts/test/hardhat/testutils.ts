import { ethers } from "hardhat";
import {
  arrayify,
  hexConcat,
  hexDataSlice,
  hexlify,
  hexZeroPad,
  Interface,
  keccak256,
  parseEther,
} from "ethers/lib/utils";
import {
  BigNumber,
  BigNumberish,
  Contract,
  ContractReceipt,
  Signer,
  Wallet,
} from "ethers";
import {
  EntryPoint,
  EntryPoint__factory,
  SimpleAccount,
  SimpleAccountFactory__factory,
  SimpleAccount__factory,
  SimpleAccountFactory,
} from "../../typechain";
import { BytesLike, Hexable } from "@ethersproject/bytes";
import { expect } from "chai";
import { UserOperation } from "./UserOperation";
import { packUserOp, simulateValidation } from "./UserOp";

export const AddressZero = ethers.constants.AddressZero;
export const HashZero = ethers.constants.HashZero;
export const ONE_ETH = parseEther("1");
export const TWO_ETH = parseEther("2");
export const FIVE_ETH = parseEther("5");

export const tostr = (x: any): string => (x != null ? x.toString() : "null");

export function tonumber(x: any): number {
  try {
    return parseFloat(x.toString());
  } catch (e: any) {
    console.log("=== failed to parseFloat:", x, e.message);
    return NaN;
  }
}

// just throw 1eth from account[0] to the given address (or contract instance)
export async function fund(
  contractOrAddress: string | Contract,
  amountEth = "1"
): Promise<void> {
  let address: string;
  if (typeof contractOrAddress === "string") {
    address = contractOrAddress;
  } else {
    address = contractOrAddress.address;
  }
  await ethers.provider
    .getSigner()
    .sendTransaction({ to: address, value: parseEther(amountEth) });
}

export async function getBalance(address: string): Promise<number> {
  const balance = await ethers.provider.getBalance(address);
  return parseInt(balance.toString());
}

let counter = 0;

// create non-random account, so gas calculations are deterministic
export function createAccountOwner(): Wallet {
  const privateKey = keccak256(
    Buffer.from(arrayify(BigNumber.from(++counter)))
  );
  return new ethers.Wallet(privateKey, ethers.provider);
  // return new ethers.Wallet('0x'.padEnd(66, privkeyBase), ethers.provider);
}

export function createAddress(): string {
  return createAccountOwner().address;
}

export function callDataCost(data: string): number {
  return ethers.utils
    .arrayify(data)
    .map((x) => (x === 0 ? 4 : 16))
    .reduce((sum, x) => sum + x);
}

export async function calcGasUsage(
  rcpt: ContractReceipt,
  entryPoint: EntryPoint,
  beneficiaryAddress?: string
): Promise<{ actualGasCost: BigNumberish }> {
  const actualGas = await rcpt.gasUsed;
  const logs = await entryPoint.queryFilter(
    entryPoint.filters.UserOperationEvent(),
    rcpt.blockHash
  );
  const { actualGasCost, actualGasUsed } = logs[0].args;
  console.log("\t== actual gasUsed (from tx receipt)=", actualGas.toString());
  console.log("\t== calculated gasUsed (paid to beneficiary)=", actualGasUsed);
  const tx = await ethers.provider.getTransaction(rcpt.transactionHash);
  console.log(
    "\t== gasDiff",
    actualGas.toNumber() - actualGasUsed.toNumber() - callDataCost(tx.data)
  );
  if (beneficiaryAddress != null) {
    expect(await getBalance(beneficiaryAddress)).to.eq(
      actualGasCost.toNumber()
    );
  }
  return { actualGasCost };
}

// helper function to create the initCode to deploy the account, using our account factory.
export function getAccountInitCode(
  owner: string,
  factory: SimpleAccountFactory,
  salt = 0
): BytesLike {
  return hexConcat([
    factory.address,
    factory.interface.encodeFunctionData("createAccount", [owner, salt]),
  ]);
}

// given the parameters as AccountDeployer, return the resulting "counterfactual address" that it would create.
export async function getAccountAddress(
  owner: string,
  factory: SimpleAccountFactory,
  salt = 0
): Promise<string> {
  return await factory.getAddress(owner, salt);
}

const panicCodes: { [key: number]: string } = {
  // from https://docs.soliditylang.org/en/v0.8.0/control-structures.html
  0x01: "assert(false)",
  0x11: "arithmetic overflow/underflow",
  0x12: "divide by zero",
  0x21: "invalid enum value",
  0x22: "storage byte array that is incorrectly encoded",
  0x31: ".pop() on an empty array.",
  0x32: "array sout-of-bounds or negative index",
  0x41: "memory overflow",
  0x51: "zero-initialized variable of internal function type",
};

// Deploys an implementation and a proxy pointing to this implementation
export async function createAccount(
  ethersSigner: Signer,
  accountOwner: string,
  entryPoint: string,
  _factory?: SimpleAccountFactory
): Promise<{
  proxy: SimpleAccount;
  accountFactory: SimpleAccountFactory;
  implementation: string;
}> {
  const accountFactory =
    _factory ??
    (await new SimpleAccountFactory__factory(ethersSigner).deploy(entryPoint));
  const implementation = await accountFactory.accountImplementation();
  await accountFactory.createAccount(accountOwner, 0);
  const accountAddress = await accountFactory.getAddress(accountOwner, 0);
  const proxy = SimpleAccount__factory.connect(accountAddress, ethersSigner);
  return {
    implementation,
    accountFactory,
    proxy,
  };
}

export function packAccountGasLimits(
  verificationGasLimit: BigNumberish,
  callGasLimit: BigNumberish
): string {
  return ethers.utils.hexConcat([
    hexZeroPad(hexlify(verificationGasLimit, { hexPad: "left" }), 16),
    hexZeroPad(hexlify(callGasLimit, { hexPad: "left" }), 16),
  ]);
}

export function packPaymasterData(
  paymaster: string,
  paymasterVerificationGasLimit: BytesLike | Hexable | number | bigint,
  postOpGasLimit: BytesLike | Hexable | number | bigint,
  paymasterData: string
): string {
  return ethers.utils.hexConcat([
    paymaster,
    hexZeroPad(hexlify(paymasterVerificationGasLimit, { hexPad: "left" }), 16),
    hexZeroPad(hexlify(postOpGasLimit, { hexPad: "left" }), 16),
    paymasterData,
  ]);
}

export function unpackAccountGasLimits(accountGasLimits: string): {
  verificationGasLimit: number;
  callGasLimit: number;
} {
  return {
    verificationGasLimit: parseInt(accountGasLimits.slice(2, 34), 16),
    callGasLimit: parseInt(accountGasLimits.slice(34), 16),
  };
}

export interface ValidationData {
  aggregator: string;
  validAfter: number;
  validUntil: number;
}

export const maxUint48 = 2 ** 48 - 1;
export function parseValidationData(
  validationData: BigNumberish
): ValidationData {
  const data = hexZeroPad(BigNumber.from(validationData).toHexString(), 32);

  // string offsets start from left (msb)
  const aggregator = hexDataSlice(data, 32 - 20);
  let validUntil = parseInt(hexDataSlice(data, 32 - 26, 32 - 20));
  if (validUntil === 0) {
    validUntil = maxUint48;
  }
  const validAfter = parseInt(hexDataSlice(data, 0, 6));

  return {
    aggregator,
    validAfter,
    validUntil,
  };
}

export function packValidationData(validationData: ValidationData): BigNumber {
  return BigNumber.from(validationData.validAfter)
    .shl(48)
    .add(validationData.validUntil)
    .shl(160)
    .add(validationData.aggregator);
}
