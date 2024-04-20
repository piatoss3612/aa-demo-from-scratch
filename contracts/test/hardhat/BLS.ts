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
import { DefaultsForUserOp, packUserOp } from "./UserOp";
import { expect } from "chai";
import { keccak256 } from "ethereumjs-util";
import { hashToPoint } from "@thehubbleproject/bls/dist/mcl";
import { BigNumber, Signer } from "ethers";
import { BytesLike, hexValue } from "@ethersproject/bytes";

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

describe("BLS Account", () => {
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
  });

  it("getTrailingPublicKey", async () => {
    const data = defaultAbiCoder.encode(["uint[6]"], [[1, 2, 3, 4, 5, 6]]);
    const last4 = await blsAgg.getTrailingPublicKey(data);
    expect(last4.map((x) => x.toNumber())).to.eql([3, 4, 5, 6]);
  });

  it("aggregateSignatures", async () => {
    const sig1 = signer1.sign("0x1234");
    const sig2 = signer2.sign("0x5678");
    const offChainSigResult = hexConcat(aggregate([sig1, sig2]));
    const userOp1 = packUserOp({
      ...DefaultsForUserOp,
      signature: hexConcat(sig1),
    });
    const userOp2 = packUserOp({
      ...DefaultsForUserOp,
      signature: hexConcat(sig2),
    });
    const solidityAggResult = await blsAgg.aggregateSignatures([
      userOp1,
      userOp2,
    ]);
    expect(solidityAggResult).to.equal(offChainSigResult);
  });
});
