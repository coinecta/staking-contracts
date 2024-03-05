import { Blockfrost, Constr, Data, Lucid, Network, Script, applyParamsToScript, fromHex, fromText, toHex, C, toText, Credential as LCredential } from "https://deno.land/x/lucid@0.10.7/mod.ts";
const { hash_blake2b256 } = C;
import { config } from "https://deno.land/x/dotenv@v3.2.2/mod.ts";
import stakingValidatorsBP from "../../plutus.json" with { type: "json" };
import { Signature, Rational, MultisigScript, DataConvert, Credential, Address, StakeCredential, Destination, NoDatum, DatumHash, InlineDatum } from "./Datums.ts";
import { abbreviatedAmount, add_reward, floorToSecond, powBigInt, timeToDatestring } from "./Utils.ts";

const env = config();

const reference_prefix = "000643b0";
const stake_key_prefix = "000de140";

const cnctPolicyId = "8b05e87a51c1d4a0fa888d2bb14dbc25e8c343ea379a171b63aa84a0";
const cnctAssetName = "434e4354";
const RewardSettingSchema = Data.Object({
    ms_locked: Data.Integer(),
    reward_multiplier: Data.Any(),
});
type RewardSetting = Data.Static<typeof RewardSettingSchema>;
const RewardSetting = RewardSettingSchema as unknown as RewardSetting;
const StakePoolDatumSchema = Data.Object({
    reward_settings: Data.Array(RewardSettingSchema),
    policy_id: Data.Bytes(),
    asset_name: Data.Bytes(),
    owner: Data.Any(),
    decimals: Data.Integer(),
});
type StakePoolDatum = Data.Static<typeof StakePoolDatumSchema>;
const StakePoolDatum = StakePoolDatumSchema as unknown as StakePoolDatum;

const StakePoolProxyDatumSchema = Data.Object({
    owner: Data.Any(),
    destination: Data.Any(),
    ms_locked: Data.Integer(),
    reward_multiplier: Data.Any(),
    policy_id: Data.Bytes(),
    asset_name: Data.Bytes(),
    nft_policy_id: Data.Bytes(),
});

type StakePoolProxyDatum = Data.Static<typeof StakePoolProxyDatumSchema>;
const StakePoolProxyDatum = StakePoolProxyDatumSchema as unknown as StakePoolProxyDatum;

const StakePoolRedeemerSchema = Data.Object({
    reward_index: Data.Integer()
});
type StakePoolRedeemer = Data.Static<typeof StakePoolRedeemerSchema>;
const StakePoolRedeemer = StakePoolRedeemerSchema as unknown as StakePoolRedeemer;

const LockDatumSchema = Data.Object({
    lock_until: Data.Integer(),
    time_lock_key: Data.Bytes(),
});
type LockDatum = Data.Static<typeof LockDatumSchema>;
const LockDatum = LockDatumSchema as unknown as LockDatum;

const TimeLockMetadataSchema = Data.Map(Data.Bytes(), Data.Bytes());
type TimeLockMetadata = Data.Static<typeof TimeLockMetadataSchema>;
const TimeLockMetadata = TimeLockMetadataSchema as unknown as TimeLockMetadata;

const TimeLockDatumSchema = Data.Object({
    metadata: TimeLockMetadataSchema,
    version: Data.Integer(),
    extra: LockDatumSchema
});
type TimeLockDatum = Data.Static<typeof TimeLockDatumSchema>;
const TimeLockDatum = TimeLockDatumSchema as unknown as TimeLockDatum;

const StakeKeyMintRedeemerSchema = Data.Object({
    stake_pool_index: Data.Integer(),
    time_lock_index: Data.Integer()
});
type StakeKeyMintRedeemer = Data.Static<typeof StakeKeyMintRedeemerSchema>;
const StakeKeyMintRedeemer = StakeKeyMintRedeemerSchema as unknown as StakeKeyMintRedeemer;

const TransactionIdSchema = Data.Object({
    hash: Data.Bytes(),
});
type TransactionId = Data.Static<typeof TransactionIdSchema>;
const TransactionId = TransactionIdSchema as unknown as TransactionId;

const OutputReferenceSchema = Data.Object({
    transaction_id: TransactionIdSchema,
    output_index: Data.Integer(),
});
type OutputReference = Data.Static<typeof OutputReferenceSchema>;
const OutputReference = OutputReferenceSchema as unknown as OutputReference;



const lucid = await Lucid.new(
    new Blockfrost("https://cardano-preview.blockfrost.io/api/v0", env["BLOCKFROST_API_KEY"]!),
    env["BLOCKFROST_NETWORK"]! as Network,
);

lucid.selectWalletFromSeed(env["MNEMONIC"]!);

const walletAddress = await lucid.wallet.address();
const walletAddressDetails = lucid.utils.getAddressDetails(walletAddress);

const batchingCertificatePolicy = lucid.utils.nativeScriptFromJson(
    {
        type: "all",
        scripts: [
            { type: "sig", keyHash: walletAddressDetails.paymentCredential?.hash },
        ],
    },
);

const batchingCertificatePolicyId = lucid.utils.mintingPolicyToId(batchingCertificatePolicy);
const batchingSubject = batchingCertificatePolicyId + fromText("CERTIFICATE");

const stakingValidatorScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(stakingValidatorsBP.validators[1].compiledCode, [stakingValidatorsBP.validators[3].hash]),
};

const stakingProxyValidatorScript: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(stakingValidatorsBP.validators[2].compiledCode, [stakingValidatorsBP.validators[3].hash, batchingSubject]),
};

const timeLockValidatorScript: Script = {
    type: "PlutusV2",
    script: stakingValidatorsBP.validators[3].compiledCode,
};

const stakingMintPolicy: Script = {
    type: "PlutusV2",
    script: applyParamsToScript(stakingValidatorsBP.validators[0].compiledCode, [stakingValidatorsBP.validators[3].hash, stakingValidatorsBP.validators[1].hash]),
};

const stakingValidatorAddress = lucid.utils.validatorToAddress(
    stakingValidatorScript,
);

const stakingProxyValidatorAddress = lucid.utils.validatorToAddress(
    stakingProxyValidatorScript,
);

const timeLockValidatorAddress = lucid.utils.validatorToAddress(
    timeLockValidatorScript,
);

const stakingMintPolicyId = lucid.utils.mintingPolicyToId(stakingMintPolicy);
const cnctSubject = cnctPolicyId + cnctAssetName;
const stakingValidatorAddressDetails = lucid.utils.getAddressDetails(stakingValidatorAddress);
const stakingProxyValidatorAddressDetails = lucid.utils.getAddressDetails(stakingProxyValidatorAddress);

console.log("Wallet address:", walletAddress);
console.log("Staking Validator Address:", stakingValidatorAddress);
console.log("Staking Validator Key Hash:", stakingValidatorAddressDetails.paymentCredential?.hash);
console.log("Staking Proxy Validator Address:", stakingProxyValidatorAddress);
console.log("Staking Proxy Validator Key Hash:", stakingProxyValidatorAddressDetails.paymentCredential?.hash);
console.log("TimeLock Validator Address:", timeLockValidatorAddress);
console.log("Staking Mint Policy Id:", stakingMintPolicyId);
console.log("CNCT PolicyId", cnctPolicyId);
console.log("CNCT AssetName", cnctAssetName);
console.log("Mint Certificate Policy Id:", batchingCertificatePolicyId);

const cnctMintingPolicy = lucid.utils.nativeScriptFromJson(
    {
        type: "all",
        scripts: [
            { type: "sig", keyHash: walletAddressDetails.paymentCredential?.hash },
            {
                type: "before",
                slot: lucid.utils.unixTimeToSlot(1704734780998),
            },
        ],
    },
);

if (Deno.args[0] === "--mint-cnct") {
    const policyId = lucid.utils.mintingPolicyToId(cnctMintingPolicy);
    const cnctSubject = policyId + fromText("CNCT");

    const tx = await lucid.newTx()
        .mintAssets({ [cnctSubject]: 800000000000n })
        .validTo(Date.now() + 200000)
        .attachMintingPolicy(cnctMintingPolicy)
        .complete();

    const signedTx = await tx.sign().complete();

    const txHash = await signedTx.submit();
    console.log("Minting CNCT:", txHash);
    await lucid.provider.awaitTx(txHash);
    console.log("Minting CNCT confirmed");
}

if (Deno.args[0] === "--create-stake-pool") {
    const stakePoolDatum: StakePoolDatum = {
        owner: new Signature(walletAddressDetails.paymentCredential?.hash!).toData(),
        policy_id: cnctPolicyId,
        asset_name: cnctAssetName,
        reward_settings: [
            {
                ms_locked: 1000n * 60n * 5n, // 5 minutes
                reward_multiplier: new Rational(5n, 100n).toData() // 5%
            }
        ],
        decimals: 0n
    };

    const tx = await lucid
        .newTx()
        .payToContract(stakingValidatorAddress, { inline: Data.to(stakePoolDatum, StakePoolDatum) }, { [cnctSubject]: 100000n })
        .complete();

    const signedTx = await tx.sign().complete();
    const txHash = await signedTx.submit();
    console.log(`Create stake pool ${txHash}, waiting for confirmation...`);
    await lucid.provider.awaitTx(txHash);

    console.log("Create stake pool complete");
}

if (Deno.args[0] === "--stake") {
    const stakePoolProxyDatum: StakePoolProxyDatum = {
        owner: new Signature(walletAddressDetails.paymentCredential!.hash).toData(),
        policy_id: cnctPolicyId,
        asset_name: cnctAssetName,
        nft_policy_id: stakingMintPolicyId,
        ms_locked: 1000n * 60n * 5n, // 5 minutes,
        reward_multiplier: new Rational(5n, 100n).toData(), // 5%
        destination: new Destination(
            new Address(
                new Credential(walletAddressDetails.paymentCredential!.hash),
                new StakeCredential(new Credential(walletAddressDetails.stakeCredential!.hash))
            ),
            new NoDatum()
        ).toData()
    };

    const tx = await lucid
        .newTx()
        .payToContract(stakingProxyValidatorAddress, { inline: Data.to(stakePoolProxyDatum, StakePoolProxyDatum) }, { [cnctSubject]: 1000n, "lovelace": 5000000n })
        .complete();

    const signedTx = await tx.sign().complete();
    const txHash = await signedTx.submit();
    console.log(`Stake ${txHash}, waiting for confirmation...`);
    await lucid.provider.awaitTx(txHash);

    console.log("Stake complete");
}

if (Deno.args[0] === "--cancel-stake") {
    const utxosAtValidator = await lucid.utxosAt(stakingProxyValidatorAddress);
    console.log("UTXOs at validator: ", utxosAtValidator);
    const myUtxos = utxosAtValidator.filter((utxo) => {
        if (utxo.datum !== null && utxo.datum !== undefined) {
            try {
                const _stakePoolDatum = Data.from(utxo.datum, StakePoolProxyDatum);
                const _ownerMultisigDatum = DataConvert.fromData<Signature>(_stakePoolDatum.owner, Signature);
                if (_ownerMultisigDatum.key_hash === walletAddressDetails.paymentCredential?.hash) {
                    return true;
                }
            }
            catch {
                return false;
            }
        }
        return false;
    });

    console.log("My UTXOs: ", myUtxos);

    const unlockTx = await lucid
        .newTx()
        .collectFrom([myUtxos[0]], Data.void())
        .attachSpendingValidator(stakingProxyValidatorScript)
        .addSigner(walletAddress)
        .complete();

    const signedUnlockTx = await unlockTx.sign().complete();
    const txUnlockHash = await signedUnlockTx.submit();
    console.log(`Unlocking ${txUnlockHash}, waiting for confirmation...`);
    await lucid.provider.awaitTx(txUnlockHash);
}

if (Deno.args[0] === "--unlock-pool") {
    const utxosAtValidator = await lucid.utxosAt(stakingValidatorAddress);
    console.log("UTXOs at Pool Validator: ", utxosAtValidator);
    const myUtxos = utxosAtValidator.filter((utxo) => {
        if (utxo.datum !== null && utxo.datum !== undefined) {
            try {
                const _stakePoolDatum = Data.from(utxo.datum, StakePoolDatum);
                const _ownerMultisigDatum = DataConvert.fromData(_stakePoolDatum.owner, Signature);
                const _rewardSettings = _stakePoolDatum.reward_settings;
                const _rewardMultiplier = DataConvert.fromData(_rewardSettings[0].reward_multiplier, Rational);
                console.log({ _ownerMultisigDatum, _rewardMultiplier });
                if (_ownerMultisigDatum.key_hash === walletAddressDetails.paymentCredential?.hash) {
                    return true;
                }
            }
            catch {
                return false;
            }
        }
        return false;
    });

    console.log("My Pool UTXOs: ", myUtxos);

    const unlockTx = await lucid
        .newTx()
        .collectFrom([myUtxos[0]], Data.to({ reward_index: 0n }, StakePoolRedeemer))
        .attachSpendingValidator(stakingValidatorScript)
        .addSigner(walletAddress)
        .complete();

    const signedUnlockTx = await unlockTx.sign().complete();
    const txUnlockHash = await signedUnlockTx.submit();
    console.log(`Unlocking ${txUnlockHash}, waiting for confirmation...`);
    await lucid.provider.awaitTx(txUnlockHash);
}

if (Deno.args[0] === "--execute-stake") {
    const bLucid = await Lucid.new(
        new Blockfrost("https://cardano-preview.blockfrost.io/api/v0", env["BLOCKFROST_API_KEY"]!),
        env["BLOCKFROST_NETWORK"]! as Network,
    );

    bLucid.selectWalletFromSeed(env["BATCHER_MNEMONIC"]!);
    const bWalletAddress = await bLucid.wallet.address();

    while (true) {
        console.clear();
        console.log("[Coinceta Catcher]");
        console.log("Catcher Wallet Address:", bWalletAddress);
        const stakeProxyUtxos = await bLucid.utxosAt(stakingProxyValidatorAddress);
        const validStakeProxyUtxos = stakeProxyUtxos.filter((utxo) => {
            if (utxo.datum !== null && utxo.datum !== undefined) {
                try {
                    const _stakePoolDatum = Data.from(utxo.datum, StakePoolProxyDatum);
                    const _ownerMultisigDatum = DataConvert.fromData(_stakePoolDatum.owner, Signature);
                    if (_ownerMultisigDatum.key_hash !== undefined) {
                        return true;
                    }
                }
                catch {
                    return false;
                }
            }
            return false;
        });
        console.log("Stake Proxy UTXOs", stakeProxyUtxos);
        console.log("Valid Stake Proxy UTXOs: ", validStakeProxyUtxos);

        const stakePoolUtxos = await bLucid.utxosAt(stakingValidatorAddress);
        const validStakePoolUtxos = stakePoolUtxos.filter((utxo) => {
            if (utxo.datum !== null && utxo.datum !== undefined) {
                try {
                    const _stakePoolDatum = Data.from(utxo.datum, StakePoolDatum);
                    const _stakePoolOwnerMultisigDatum = DataConvert.fromData(_stakePoolDatum.owner, Signature);
                    if (_stakePoolOwnerMultisigDatum.key_hash === walletAddressDetails.paymentCredential?.hash) {
                        return true;
                    }
                }
                catch {
                    return false;
                }
            }
            return false;
        });

        console.log("Valid Stake Pool UTXOs: ", validStakePoolUtxos);

        if (validStakePoolUtxos.length === 0 || validStakeProxyUtxos.length === 0) {
            console.log("No valid stake pool or stake proxy UTXOs found, waiting for 20 seconds...");
            await new Promise((resolve) => setTimeout(resolve, 20000));
            continue;
        }

        const stakePoolUtxo = validStakePoolUtxos[0];
        const stakeProxyUtxo = validStakeProxyUtxos[0];

        const stakeNftAssetName = toHex(hash_blake2b256(fromHex(Data.to({
            transaction_id: {
                hash: stakePoolUtxo.txHash,
            },
            output_index: BigInt(stakePoolUtxo.outputIndex),
        }, OutputReference)))).substring(0, 56);

        const stakeOrderDatum = Data.from(stakeProxyUtxo.datum!, StakePoolProxyDatum);
        const stakePoolDatum = Data.from(stakePoolUtxo.datum!, StakePoolDatum);
        const poolAmount = stakePoolUtxo.assets[cnctSubject];
        const stakeAmount = stakeProxyUtxo.assets[cnctSubject];
        const rewardMultiplier = DataConvert.fromData(stakeOrderDatum.reward_multiplier, Rational);
        const rewardTotal = add_reward(stakeAmount, rewardMultiplier);
        const newStakePoolAmount = poolAmount - (rewardTotal - stakeAmount);
        const amountWithDecimals = rewardTotal / powBigInt(10n, stakePoolDatum.decimals);
        const destination = DataConvert.fromData(stakeOrderDatum.destination, Destination);
        const destinationAddressPaymentKeyHash = destination.address?.payment_credential?.hash!;
        const destinationAddressStakeKeyHash = destination.address?.stake_credential?.credential?.hash!;
        const destinationAddress = lucid.utils.credentialToAddress(
            {
                type: "Key",
                hash: destinationAddressPaymentKeyHash
            },
            destinationAddressStakeKeyHash != undefined ? {
                type: "Key",
                hash: destinationAddressStakeKeyHash
            } : undefined);

        const currentSlot = lucid.currentSlot() - 100; // Subtract 100 slots to account for latency around 5 minutes and for some reason lucid returns a slot that is in the future
        const currentTime = floorToSecond(lucid.utils.slotToUnixTime(currentSlot));
        const validTime = BigInt(floorToSecond(currentTime + (1000 * 60 * 7))); // Add seven minutes to upper bound of tx validity
        const lockTime = validTime + stakeOrderDatum.ms_locked;
        console.log("Current Slot", currentSlot);
        console.log("Current Time", currentTime);
        console.log("Valid Time", validTime);
        console.log("Lock Time", lockTime);

        const metadata_name =
            "Stake NFT " +
            abbreviatedAmount(amountWithDecimals, 0n) + " " +
            toText(stakePoolDatum.asset_name) + " - " +
            timeToDatestring(lockTime);

        const timelockMetadata: TimeLockMetadata = new Map([
            [fromText("locked_amount"), fromText(rewardTotal.toString())],
            [fromText("name"), fromText(metadata_name)]
        ]);

        console.log("Stake NFT Asset Name", stakeNftAssetName, stakePoolUtxo.txHash, stakePoolUtxo.outputIndex);
        console.log("Reward Total", rewardTotal);
        console.log("Reward with decimals", amountWithDecimals);
        console.log("Reward with decimals CBOR", Data.to(amountWithDecimals));
        console.log("Stake Amount", stakeAmount);
        console.log("Pool Amount", poolAmount);
        console.log("New Pool Amount", newStakePoolAmount);
        console.log("Metadata Name", metadata_name, lockTime);
        console.log("Timelock Metadata", Data.to(timelockMetadata, TimeLockMetadata));
        console.log("Destination Address", destinationAddress);

        const tx = await bLucid
            .newTx()
            .validFrom(currentTime)
            .validTo(parseInt((validTime).toString()))
            .collectFrom([stakePoolUtxo], Data.to({ reward_index: 0n }, StakePoolRedeemer))
            .collectFrom([stakeProxyUtxo], Data.void())
            .mintAssets({
                [stakingMintPolicyId + stake_key_prefix + stakeNftAssetName]: 1n,
                [stakingMintPolicyId + reference_prefix + stakeNftAssetName]: 1n
            }, Data.to({
                stake_pool_index: 0n,
                time_lock_index: 1n,
            }, StakeKeyMintRedeemer))
            .payToContract(stakingValidatorAddress, { inline: Data.to(stakePoolDatum, StakePoolDatum) }, { [cnctSubject]: newStakePoolAmount })
            .payToContract(timeLockValidatorAddress, {
                inline: Data.to({
                    metadata: timelockMetadata,
                    version: 1n,
                    extra: {
                        lock_until: lockTime,
                        time_lock_key: stakingMintPolicyId + stake_key_prefix + stakeNftAssetName,
                    }
                }, TimeLockDatum)
            }, {
                [cnctSubject]: rewardTotal,
                [stakingMintPolicyId + reference_prefix + stakeNftAssetName]: 1n
            })
            .payToAddress(bWalletAddress, {
                [batchingSubject]: 1n
            })
            .payToAddress(destinationAddress, { [stakingMintPolicyId + stake_key_prefix + stakeNftAssetName]: 1n })
            .attachSpendingValidator(stakingValidatorScript)
            .attachSpendingValidator(stakingProxyValidatorScript)
            .attachMintingPolicy(stakingMintPolicy)
            .complete({
                nativeUplc: true
            });

        const signedTx = await tx.sign().complete();
        const txHash = await signedTx.submit();
        console.log(`Execute stake ${txHash}, waiting for confirmation...`);
        await lucid.provider.awaitTx(txHash);
        console.log("Execute stake complete, waiting for 40 seconds...");
        await new Promise((resolve) => setTimeout(resolve, 40000));
    }
}

if (Deno.args[0] === "--unlock-stake") {
    const utxosAtValidator = await lucid.utxosAt(timeLockValidatorAddress);
    console.log("UTXOs at validator: ", utxosAtValidator);
    const myUtxos = utxosAtValidator.filter((utxo) => {
        if (utxo.datum !== null && utxo.datum !== undefined) {
            try {
                const _lockDatum = Data.from(utxo.datum, TimeLockDatum);
                return true;
            }
            catch {
                return false;
            }
        }
        return false;
    });

    console.log("My UTXOs: ", myUtxos);
    const lockDatum = Data.from(myUtxos[0].datum!, TimeLockDatum);
    const stake_key = lockDatum.extra.time_lock_key;
    const asset_name = lockDatum.extra.time_lock_key.replace(stakingMintPolicyId + stake_key_prefix, "");
    const reference_key = stakingMintPolicyId + reference_prefix + asset_name;

    const currentTime = lucid.utils.slotToUnixTime(lucid.currentSlot());
    const bufferTime = currentTime + 3_600_000;
    console.log(lockDatum.extra.lock_until, bufferTime);
    const unlockTx = await lucid
        .newTx()
        .validFrom(parseInt(lockDatum.extra.lock_until.toString()))
        .validTo(parseInt(bufferTime.toString()))
        .collectFrom([myUtxos[0]], Data.void())
        .mintAssets({
            [stake_key]: -1n,
            [reference_key]: -1n
        }, Data.to({
            stake_pool_index: 0n,
            time_lock_index: 0n,
        }, StakeKeyMintRedeemer))
        .attachSpendingValidator(timeLockValidatorScript)
        .attachMintingPolicy(stakingMintPolicy)
        .complete({
            nativeUplc: true
        });
    const signedUnlockTx = await unlockTx.sign().complete();
    const txUnlockHash = await signedUnlockTx.submit();
    console.log(`Unlocking ${txUnlockHash}, waiting for confirmation...`);
    await lucid.provider.awaitTx(txUnlockHash);
}

if (Deno.args[0] === "--setup-collateral") {
    const tx = await lucid
        .newTx()
        .payToAddress(walletAddress, { lovelace: 5000000n })
        .complete();

    const signedTx = await tx.sign().complete();
    const txHash = await signedTx.submit();
    console.log(`Setup collateral ${txHash}, waiting for confirmation...`);
    await lucid.provider.awaitTx(txHash);

    console.log("Setup collateral complete");
}

if (Deno.args[0] === "--mint-certificate") {
    const tx = await lucid
        .newTx()
        .mintAssets({ [batchingSubject]: 1n })
        .attachMintingPolicy(batchingCertificatePolicy)
        .payToAddress("addr_test1qpg007fw5caetatd8gxcyt6d08lzteh9afk5smfd9hr60l72udjv5rtpfksjl64zeay5f2gpj6st0tl8m400nq8hjp9suxaw6c", { [batchingSubject]: 1n })
        .complete();

    const signedTx = await tx.sign().complete();
    const txHash = await signedTx.submit();
    console.log(`Mint certificate ${txHash}, waiting for confirmation...`);
    await lucid.provider.awaitTx(txHash);

    console.log("Mint certificate complete");
}

if (Deno.args[0] === "--mint-stake-key-hack") {
    const tx = await lucid
        .newTx()
        .mintAssets({ [stakingMintPolicyId + "9e7a86"]: 1n }, Data.to({
            stake_pool_index: 0n,
            time_lock_index: 0n,
        }, StakeKeyMintRedeemer))
        .attachMintingPolicy(stakingMintPolicy)
        .complete();

    const signedTx = await tx.sign().complete();
    const txHash = await signedTx.submit();
    console.log(`Mint stake key hack ${txHash}, waiting for confirmation...`);
    await lucid.provider.awaitTx(txHash);
}

if (Deno.args[0] === "--test") {
    console.log(walletAddressDetails.paymentCredential?.hash);
    const signature: MultisigScript = new Signature(walletAddressDetails.paymentCredential?.hash!);

    const stakePoolDatum: StakePoolDatum = {
        owner: new Constr(0, ["0c61f135f652bc17994a5411d0a256de478ea24dbc19759d2ba14f03"]),
        policy_id: "8b05e87a51c1d4a0fa888d2bb14dbc25e8c343ea379a171b63aa84a0",
        asset_name: "434e4354",
        reward_settings: [
            {
                ms_locked: 100n,
                reward_multiplier: new Rational(5n, 100n).toData()
            }
        ],
        decimals: 6n
    };

    const rationalTest = new Rational(5n, 100n).toData();
    const rewardSetting: RewardSetting = {
        ms_locked: 100n,
        reward_multiplier: new Rational(5n, 100n).toData()
    };

    console.log("Reward Setting Type", Data.to(rewardSetting, RewardSetting));
    console.log("Rational Type", Data.to(rationalTest));
    console.log("Multisig Signature Type", signature.toData());
    console.log("Multisig Signature Type Cbor", Data.to(signature.toData()));
    console.log("Stake Pool Datum Type", Data.to(stakePoolDatum, StakePoolDatum));
    console.log("Policy", cnctPolicyId);
    console.log("Asset", cnctAssetName);

    const credential = new Credential("cb84310092f8c3dae1ebf0ac456114e487297d3fe684d3236588d5b3");
    console.log("Credential", Data.to(credential.toData()));

    const stakeCredential = new StakeCredential(credential);
    console.log("Stake Credential", Data.to(stakeCredential.toData()));

    const addressWithStake = new Address(
        credential,
        new StakeCredential(credential)
    )
    console.log("Address with Stake", Data.to(addressWithStake.toData()));

    const addressWithNoStake = new Address(
        credential
    );
    console.log("Address with No Stake", Data.to(addressWithNoStake.toData()));

    const destinationNoDatum = new Destination(
        addressWithNoStake,
        new NoDatum()
    );
    console.log("Destination No Datum", Data.to(destinationNoDatum.toData()));

    const inlineDatumCredential = new InlineDatum(credential.toData());
    console.log("Inline Datum with Credential", Data.to(inlineDatumCredential.toData()));

    const destinationWithDatum = new Destination(
        addressWithStake,
        inlineDatumCredential
    );

    console.log("Destination with Datum", Data.to(destinationWithDatum.toData()));

    const stakePoolProxyDatum: StakePoolProxyDatum = {
        owner: new Signature("cb84310092f8c3dae1ebf0ac456114e487297d3fe684d3236588d5b3").toData(),
        policy_id: cnctPolicyId,
        asset_name: cnctAssetName,
        nft_policy_id: stakingMintPolicyId,
        ms_locked: 1000n,
        reward_multiplier: new Rational(1n, 100n).toData(),
        destination: new Destination(
            new Address(
                credential,
                new StakeCredential(credential)
            ),
            new NoDatum()
        ).toData()
    };

    console.log("Stake Pool Proxy Datum Destination NoDatum", Data.to(stakePoolProxyDatum, StakePoolProxyDatum));

    const stakePoolProxyDatumWithDatum: StakePoolProxyDatum = {
        owner: new Signature("cb84310092f8c3dae1ebf0ac456114e487297d3fe684d3236588d5b3").toData(),
        policy_id: cnctPolicyId,
        asset_name: cnctAssetName,
        nft_policy_id: stakingMintPolicyId,
        ms_locked: 1000n,
        reward_multiplier: new Rational(1n, 100n).toData(),
        destination: new Destination(
            new Address(
                credential,
                new StakeCredential(credential)
            ),
            new InlineDatum(credential.toData())
        ).toData()
    };

    console.log("Stake Pool Proxy Datum Destination with Datum", Data.to(stakePoolProxyDatumWithDatum, StakePoolProxyDatum));

    const outputReference: OutputReference = {
        transaction_id: {
            hash: "00000000000000000000000000000000000000000000000000000000"
        },
        output_index: 0n
    };

    console.log("Output Reference", toHex(hash_blake2b256(fromHex(Data.to(outputReference, OutputReference)))).substring(0, 56));

    const stakeAmount = 100n;
    const rewardPercent = new Rational(5n, 100n);
    const rewardAmount = add_reward(stakeAmount, rewardPercent);
    console.log("Reward Amount", rewardAmount);

    const timelockMetadata: TimeLockMetadata = new Map([
        [fromText("locked_amount"), fromText(1000n.toString())],
        [fromText("name"), fromText("Stake NFT 1K CNCT - 240123")]
    ]);

    console.log("Timelock Metadata", Data.to(timelockMetadata, TimeLockMetadata));

    const noDatum = new NoDatum();
    console.log("No Datum", Data.to(noDatum.toData()));

    const datumHash = new DatumHash("6c00ac8ecdbfad86c9287b2aec257f2e3875b572de8d8df27fd94dd650671c94");
    console.log("Datum Hash", Data.to(datumHash.toData()));

    const inlineDatumAddress = new InlineDatum(addressWithStake.toData());
    console.log("Inline Datum with Address", Data.to(inlineDatumAddress.toData()));

    const lockDatum: LockDatum = {
        lock_until: 1000n,
        time_lock_key: "6c00ac8ecdbfad86c9287b2aec257f2e3875b572de8d8df27fd94dd650671c94"
    };

    console.log("Lock Datum", Data.to(lockDatum, LockDatum));

    const timelock: TimeLockDatum = {
        metadata: timelockMetadata,
        version: 1n,
        extra: lockDatum
    };

    console.log("TimeLock Datum", Data.to(timelock, TimeLockDatum));

}