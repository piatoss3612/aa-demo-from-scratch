import {
  aggregate,
  BlsSignerFactory,
  BlsVerifier,
} from "@thehubbleproject/bls/dist/signer";
import { arrayify, defaultAbiCoder, hexConcat } from "ethers/lib/utils";
import {
  BLSOpen__factory,
  BLSSignatureAggregator,
  BLSSignatureAggregator__factory,
  BLSAccount,
  BLSAccount__factory,
  BLSAccountFactory,
  BLSAccountFactory__factory,
  EntryPoint,
  EntryPoint__factory,
} from "../../typechain";
import { ethers } from "hardhat";
import { createAddress, fund, ONE_ETH } from "./testutils";
import { DefaultsForUserOp, packUserOp, fillAndPack } from "./UserOp";
import { UserOpsPerAggregator } from "./UserOperation";
import { expect } from "chai";
import { keccak256 } from "ethereumjs-util";
import { hashToPoint } from "@thehubbleproject/bls/dist/mcl";
import { BigNumber, Signer } from "ethers";

async function deployBlsAccount(
  ethersSigner: Signer,
  factoryAddr: string,
  blsSigner: any
): Promise<BLSAccount> {
  const factory = BLSAccountFactory__factory.connect(factoryAddr, ethersSigner);
  const addr = await factory.callStatic.createAccount(0, blsSigner.pubkey);
  await factory.createAccount(0, blsSigner.pubkey);
  return BLSAccount__factory.connect(addr, ethersSigner);
}

describe("BLS", () => {
  const BLS_DOMAIN = arrayify(keccak256(Buffer.from("eip4337.bls.domain")));
  const etherSigner = ethers.provider.getSigner();
  let fact: BlsSignerFactory;
  let signer1: any;
  let signer2: any;
  let blsAgg: BLSSignatureAggregator;
  let entrypoint: EntryPoint;
  let account1: BLSAccount;
  let account2: BLSAccount;
  let accountDeployer: BLSAccountFactory;
  let beneficiary: string;

  before(async () => {
    entrypoint = await new EntryPoint__factory(etherSigner).deploy();
    const BLSOpenLib = await new BLSOpen__factory(etherSigner).deploy();
    blsAgg = await new BLSSignatureAggregator__factory(
      {
        "src/bls/lib/BLSOpen.sol:BLSOpen": BLSOpenLib.address,
      },
      etherSigner
    ).deploy(entrypoint.address);

    await blsAgg.addStake(2, { value: ONE_ETH });

    fact = await BlsSignerFactory.new();

    signer1 = fact.getSigner(arrayify(BLS_DOMAIN), "0x01");
    signer2 = fact.getSigner(arrayify(BLS_DOMAIN), "0x02");

    accountDeployer = await new BLSAccountFactory__factory(etherSigner).deploy(
      entrypoint.address,
      blsAgg.address
    );

    account1 = await deployBlsAccount(
      etherSigner,
      accountDeployer.address,
      signer1
    );
    account2 = await deployBlsAccount(
      etherSigner,
      accountDeployer.address,
      signer2
    );

    beneficiary = createAddress();
  });

  it("getTrailingPublicKey", async () => {
    // 입력으로 주어지는 data는 192 바이트 길이의 바이트열이다.
    const data = defaultAbiCoder.encode(["uint[6]"], [[1, 2, 3, 4, 5, 6]]);
    // getTrailingPublicKey는 data의 뒤에서 128 바이트를 가져와서 BLS 공개키로 변환한다.
    // 이 때 128 바이트는 길이가 4인 uint 배열로 변환되어야 한다.
    const last4 = await blsAgg.getTrailingPublicKey(data);
    expect(last4.map((x) => x.toNumber())).to.eql([3, 4, 5, 6]);
  });

  it("aggregateSignatures", async () => {
    const sig1 = signer1.sign("0x1234"); // signer1의 개인키로 "0x1234"에 대한 서명을 생성한다.
    const sig2 = signer2.sign("0x5678"); // signer2의 개인키로 "0x5678"에 대한 서명을 생성한다.

    console.log("sig1", sig1); // 64 바이트 길이의 16진수 값 - m * privkey1
    console.log("sig2", sig2); // 64 바이트 길이의 16진수 값 - m * privkey2

    const aggSig = aggregate([sig1, sig2]); // sig1과 sig2를 집계한다.

    console.log("aggSig", aggSig); // 32 바이트 * 2 크기의 배열 - [x, y] 형태의 집계된 서명

    const offChainSigResult = hexConcat(aggSig); // 집계된 서명을 16진수 문자열로 변환한다.

    console.log("offChainSigResult", offChainSigResult); // 64 바이트 길이의 16진수 값

    // 서명을 포함한 UserOp을 생성한다.
    const userOp1 = packUserOp({
      ...DefaultsForUserOp,
      signature: hexConcat(sig1),
    });

    const userOp2 = packUserOp({
      ...DefaultsForUserOp,
      signature: hexConcat(sig2),
    });

    // 온체인에서 집계된 서명을 생성한다.
    const solidityAggResult = await blsAgg.aggregateSignatures([
      userOp1,
      userOp2,
    ]);

    console.log("solidityAggResult", solidityAggResult); // 64 바이트 길이의 16진수 값

    expect(solidityAggResult).to.equal(offChainSigResult); // 집계된 서명이 같은지 확인한다.
  });

  it("userOpToMessage", async () => {
    // UserOp을 생성한다.
    const userOp1 = await fillAndPack(
      {
        sender: account1.address,
      },
      entrypoint
    );
    // UserOp의 해시를 구한다.
    const requestHash = await blsAgg.getUserOpHash(userOp1);

    console.log("requestHash", requestHash); // 32 바이트 길이의 16진수 값

    // UserOp을 메시지로 변환한다.
    const solPoint: BigNumber[] = await blsAgg.userOpToMessage(userOp1);

    console.log("solPoint", solPoint); // [x, y] 형태의 메시지

    // UserOp의 해시를 [x, y] 형태의 메시지로 변환한다.
    const messagePoint = hashToPoint(requestHash, BLS_DOMAIN);

    console.log("messagePoint", messagePoint.getStr());

    expect(`1 ${solPoint[0].toString()} ${solPoint[1].toString()}`).to.equal(
      messagePoint.getStr()
    );
  });

  it("validateUserOpSignature", async () => {
    // UserOp1을 생성한다.
    const userOp1 = await fillAndPack(
      {
        sender: account1.address,
      },
      entrypoint
    );
    // UserOp1의 해시를 구한다.
    const requestHash = await blsAgg.getUserOpHash(userOp1);

    // UserOp1의 해시에 대한 서명을 생성한다.
    const sigParts = signer1.sign(requestHash);
    // UserOp1에 서명을 추가한다.
    userOp1.signature = hexConcat(sigParts);
    // UserOp1의 서명 길이가 130인지 확인한다.

    expect(userOp1.signature.length).to.equal(130); // 0x + 64 * 2

    // 오프체인에서 서명을 검증한다.
    const verifier = new BlsVerifier(BLS_DOMAIN);
    expect(verifier.verify(sigParts, signer1.pubkey, requestHash)).to.equal(
      true
    );

    // 온체인에서 서명을 검증한다.
    const ret = await blsAgg.validateUserOpSignature(userOp1);
    expect(ret).to.equal("0x");
  });

  it("validateSignatures", async function () {
    this.timeout(30000);
    // UserOp1을 생성한다.
    const userOp1 = await fillAndPack(
      {
        sender: account1.address,
      },
      entrypoint
    );
    // UserOp1의 해시를 구한다.
    const requestHash = await blsAgg.getUserOpHash(userOp1);
    // UserOp1의 해시에 대한 서명을 생성한다.
    const sig1 = signer1.sign(requestHash);
    // UserOp1에 서명을 추가한다.
    userOp1.signature = hexConcat(sig1);

    // UserOp2을 생성한다.
    const userOp2 = await fillAndPack(
      {
        sender: account2.address,
      },
      entrypoint
    );
    // UserOp2의 해시를 구한다.
    const requestHash2 = await blsAgg.getUserOpHash(userOp2);
    // UserOp2의 해시에 대한 서명을 생성한다.
    const sig2 = signer2.sign(requestHash2);
    // UserOp2에 서명을 추가한다.
    userOp2.signature = hexConcat(sig2);

    // 오프체인에서 두 서명을 집계한다.
    const aggSig = aggregate([sig1, sig2]);
    // 온체인에서 두 서명을 집계한다.
    const aggregatedSig = await blsAgg.aggregateSignatures([userOp1, userOp2]);
    // 두 집계된 서명이 같은지 확인한다.
    expect(hexConcat(aggSig)).to.equal(aggregatedSig);

    // 두 서명자의 공개키를 가져온다.
    const pubkeys = [signer1.pubkey, signer2.pubkey];
    // BLS 검증자를 생성한다.
    const v = new BlsVerifier(BLS_DOMAIN);
    // 오프체인에서 집계된 서명을 검증한다.
    const now = Date.now();
    expect(
      v.verifyMultiple(aggSig, pubkeys, [requestHash, requestHash2])
    ).to.equal(true);
    console.log("verifyMultiple (mcl code)", Date.now() - now, "ms");

    // 온체인에서 집계된 서명을 검증한다.
    const now2 = Date.now();
    console.log(
      "validateSignatures gas= ",
      await blsAgg.estimateGas.validateSignatures(
        [userOp1, userOp2],
        aggregatedSig
      )
    );
    console.log("validateSignatures (on-chain)", Date.now() - now2, "ms");
  });

  it("handleAggregatedOps", async function () {
    this.timeout(30000);
    // UserOp1을 생성한다.
    const userOp1 = await fillAndPack(
      {
        sender: account1.address,
      },
      entrypoint
    );
    // UserOp1의 해시를 구한다.
    const requestHash = await blsAgg.getUserOpHash(userOp1);
    // UserOp1의 해시에 대한 서명을 생성한다.
    const sig1 = signer1.sign(requestHash);
    // UserOp1에 서명을 추가한다.
    userOp1.signature = hexConcat(sig1);

    // UserOp2을 생성한다.
    const userOp2 = await fillAndPack(
      {
        sender: account2.address,
      },
      entrypoint
    );
    // UserOp2의 해시를 구한다.
    const requestHash2 = await blsAgg.getUserOpHash(userOp2);
    // UserOp2의 해시에 대한 서명을 생성한다.
    const sig2 = signer2.sign(requestHash2);
    // UserOp2에 서명을 추가한다.
    userOp2.signature = hexConcat(sig2);

    // 오프체인에서 두 서명을 집계한다.
    const aggSig = aggregate([sig1, sig2]);
    // 온체인에서 두 서명을 집계한다.
    const aggregatedSig = await blsAgg.aggregateSignatures([userOp1, userOp2]);
    // 두 집계된 서명이 같은지 확인한다.
    expect(hexConcat(aggSig)).to.equal(aggregatedSig);

    // 집계된 서명과 UserOp들을 Aggregator에 전달할 수 있는 형태로 변환한다.
    const userOpsPerAgg: UserOpsPerAggregator[] = [
      {
        userOps: [userOp1, userOp2],
        aggregator: blsAgg.address,
        signature: aggregatedSig,
      },
    ];

    // BLS 계정에 자금을 추가한다. (수수료를 지불하기 위해)
    await fund(account1.address);
    await fund(account2.address);

    const now = Date.now();

    // handleAggregatedOps를 호출하여 UserOp들을 처리한다.
    const tx = await entrypoint.handleAggregatedOps(userOpsPerAgg, beneficiary);
    const receipt = await tx.wait();

    console.log("handleAggregatedOps gas= ", receipt.gasUsed);

    console.log("handleAggregatedOps", Date.now() - now, "ms");
  });

  it("handleOps", async function () {
    this.timeout(30000);
    const userOp1 = await fillAndPack(
      {
        sender: account1.address,
      },
      entrypoint
    );
    const requestHash = await blsAgg.getUserOpHash(userOp1);
    const sig1 = signer1.sign(requestHash);
    userOp1.signature = hexConcat(sig1);

    const userOp2 = await fillAndPack(
      {
        sender: account2.address,
      },
      entrypoint
    );
    const requestHash2 = await blsAgg.getUserOpHash(userOp2);
    const sig2 = signer2.sign(requestHash2);
    userOp2.signature = hexConcat(sig2);

    await fund(account1.address);
    await fund(account2.address);

    // handleOps 함수는 aggregator를 지원하는 계정을 지원하지 않는다.
    await expect(
      entrypoint.handleOps([userOp1, userOp2], beneficiary)
    ).to.be.revertedWith('FailedOp(0, "AA24 signature error")');
  });
});
