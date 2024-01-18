import { Blockfrost, Data, Lucid, Network, Script, fromHex, fromText, toHex } from "https://deno.land/x/lucid@0.10.7/mod.ts";
import { config } from "https://deno.land/x/dotenv@v3.2.2/mod.ts";

const env = config();

const reference_prefix = "000643b0";
const stake_key_prefix = "000de140";

import stakingValidatorsBP from "../../plutus.json" assert { type: "json" };

const RewardSetting = Data.Object({
    days_locked: Data.Integer(),
    percentage_reward: Data.Integer(),
});
type RewardSetting = Data.Static<typeof RewardSetting>;

const StakePoolDatumSchema = Data.Object({
    reward_settings: Data.Array(RewardSetting),
    policy_id: Data.Bytes(),
    asset_name: Data.Bytes(),
    owner: Data.Bytes(),
    decimals: Data.Integer(),
});
type StakePoolDatum = Data.Static<typeof StakePoolDatumSchema>;
const StakePoolDatum = StakePoolDatumSchema as unknown as StakePoolDatum;

const StakePoolProxyDatumSchema = Data.Object({
    owner: Data.Bytes(),
    days_locked: Data.Integer(),
    reward_percentage: Data.Integer(),
    policy_id: Data.Bytes(),
    asset_name: Data.Bytes(),
    key_policy_id: Data.Bytes(),
    key_img_url: Data.Bytes(),
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
    time_lock_index: Data.Integer(),
    stake_proxy_index: Data.Integer(),
});
type StakeKeyMintRedeemer = Data.Static<typeof StakeKeyMintRedeemerSchema>;
const StakeKeyMintRedeemer = StakeKeyMintRedeemerSchema as unknown as StakeKeyMintRedeemer;

const lucid = await Lucid.new(
    new Blockfrost("https://cardano-preview.blockfrost.io/api/v0", env["BLOCKFROST_API_KEY"]!),
    env["BLOCKFROST_NETWORK"]! as Network,
);

lucid.selectWalletFromSeed(env["MNEMONIC"]!);

const walletAddress = await lucid.wallet.address();
const walletAddressDetails = lucid.utils.getAddressDetails(walletAddress);

const stakingValidatorScript: Script = {
    type: "PlutusV2",
    script: stakingValidatorsBP.validators[1].compiledCode,
};

const stakingProxyValidatorScript: Script = {
    type: "PlutusV2",
    script: stakingValidatorsBP.validators[2].compiledCode,
};

const timeLockValidatorScript: Script = {
    type: "PlutusV2",
    script: stakingValidatorsBP.validators[3].compiledCode,
};

const stakingMintPolicy: Script = {
    type: "PlutusV2",
    script: stakingValidatorsBP.validators[0].compiledCode,
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
const cnctPolicyId = "8b05e87a51c1d4a0fa888d2bb14dbc25e8c343ea379a171b63aa84a0";
const cnctAssetName = "434e4354";
const subject = cnctPolicyId + cnctAssetName;

const abbreviatedAmount = (amount: bigint, decimals: bigint): string => {
    const ten = BigInt(10);
    const thousand = BigInt(1000);
    const million = BigInt(1000000);
    const billion = BigInt(1000000000);
    const trillion = BigInt(1000000000000);
    const quadrillion = BigInt(1000000000000000);

    const amountDec = amount / (ten ** decimals);

    if (amountDec >= quadrillion) {
        const quadrillions = amountDec / quadrillion;
        return quadrillions > 999n ? "***Q" : `${quadrillions.toString()}Q`;
    } else if (amountDec >= trillion) {
        const trillions = amountDec / trillion;
        return `${trillions.toString()}T`;
    } else if (amountDec >= billion) {
        const billions = amountDec / billion;
        return `${billions.toString()}B`;
    } else if (amountDec >= million) {
        const millions = amountDec / million;
        return `${millions.toString()}M`;
    } else if (amountDec >= thousand) {
        const thousands = amountDec / thousand;
        return `${thousands.toString()}K`;
    } else {
        return amountDec.toString();
    }
}

const timeToDatestring = (time: bigint): string => {
    const s = time / 1000n;
    const z = s / 86400n + 719468n;
    const era = (z >= 0n ? z : z - 146096n) / 146097n;
    const doe = z - era * 146097n;
    const yoe = (doe - doe / 1460n + doe / 36524n - doe / 146096n) / 365n;
    const y = yoe + era * 400n;
    const doy = doe - (365n * yoe + yoe / 4n - yoe / 100n);
    const mp = (5n * doy + 2n) / 153n;
    const d = doy - (153n * mp + 2n) / 5n + 1n;
    const m = mp + (mp < 10n ? 3n : -9n);
    const adjustedY = y + (m <= 2n ? 1n : 0n);

    const yearString = adjustedY.toString().slice(-2); // Get last two digits of the year
    const monthString = (m < 10n ? "0" : "") + m.toString();
    const dayString = (d < 10n ? "0" : "") + d.toString();

    return yearString + monthString + dayString;
}






console.log("Wallet address:", walletAddress);
console.log("Staking Validator Address:", stakingValidatorAddress);
console.log("Staking Proxy Validator Address:", stakingProxyValidatorAddress);
console.log("TimeLock Validator Address:", timeLockValidatorAddress);
console.log("Staking Mint Policy Id:", stakingMintPolicyId);

const mintingPolicy = lucid.utils.nativeScriptFromJson(
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
    const policyId = lucid.utils.mintingPolicyToId(mintingPolicy);
    const unit = policyId + fromText("CNCT");

    const tx = await lucid.newTx()
        .mintAssets({ [unit]: 800000000000n })
        .validTo(Date.now() + 200000)
        .attachMintingPolicy(mintingPolicy)
        .complete();

    const signedTx = await tx.sign().complete();

    const txHash = await signedTx.submit();
    console.log("Minting CNCT:", txHash);
    await lucid.provider.awaitTx(txHash);
    console.log("Minting CNCT confirmed");
}

if (Deno.args[0] === "--create-stake-pool") {
    const stakePoolDatum: StakePoolDatum = {
        owner: walletAddressDetails.paymentCredential!.hash,
        policy_id: cnctPolicyId,
        asset_name: cnctAssetName,
        reward_settings: [
            {
                days_locked: 1n,
                percentage_reward: 1n,
            }
        ],
        decimals: 6n
    };

    const tx = await lucid
        .newTx()
        .payToContract(stakingValidatorAddress, { inline: Data.to(stakePoolDatum, StakePoolDatum) }, { [subject]: 100000n })
        .complete();

    const signedTx = await tx.sign().complete();
    const txHash = await signedTx.submit();
    console.log(`Create stake pool ${txHash}, waiting for confirmation...`);
    await lucid.provider.awaitTx(txHash);

    console.log("Create stake pool complete");
}

if (Deno.args[0] === "--stake") {
    const stakePoolProxyDatum: StakePoolProxyDatum = {
        owner: walletAddressDetails.paymentCredential!.hash,
        policy_id: cnctPolicyId,
        asset_name: cnctAssetName,
        key_policy_id: stakingMintPolicyId,
        days_locked: 1n,
        reward_percentage: 1n,
        key_img_url: fromText("http://image.com"),
    };

    const tx = await lucid
        .newTx()
        .payToContract(stakingProxyValidatorAddress, { inline: Data.to(stakePoolProxyDatum, StakePoolProxyDatum) }, { [subject]: 1000n })
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
                if (_stakePoolDatum.owner === walletAddressDetails.paymentCredential?.hash) {
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
    console.log("UTXOs at validator: ", utxosAtValidator);
    const myUtxos = utxosAtValidator.filter((utxo) => {
        if (utxo.datum !== null && utxo.datum !== undefined) {
            try {
                const _stakePoolDatum = Data.from(utxo.datum, StakePoolDatum);
                if (_stakePoolDatum.owner === walletAddressDetails.paymentCredential?.hash) {
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
    console.log("Catcher Wallet Address:", bWalletAddress);

    while (true) {
        console.clear();
        console.log("[Coinceta Catcher]");
        const stakeProxyUtxos = await bLucid.utxosAt(stakingProxyValidatorAddress);
        const validStakeProxyUtxos = stakeProxyUtxos.filter((utxo) => {
            if (utxo.datum !== null && utxo.datum !== undefined) {
                try {
                    const _stakePoolDatum = Data.from(utxo.datum, StakePoolProxyDatum);
                    if (_stakePoolDatum.owner === walletAddressDetails.paymentCredential?.hash) {
                        return true;
                    }
                }
                catch {
                    return false;
                }
            }
            return false;
        });

        console.log("Valid Stake Proxy UTXOs: ", validStakeProxyUtxos);

        const stakePoolUtxos = await bLucid.utxosAt(stakingValidatorAddress);
        const validStakePoolUtxos = stakePoolUtxos.filter((utxo) => {
            if (utxo.datum !== null && utxo.datum !== undefined) {
                try {
                    const _stakePoolDatum = Data.from(utxo.datum, StakePoolDatum);
                    if (_stakePoolDatum.owner === walletAddressDetails.paymentCredential?.hash) {
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
            console.log("No valid stake pool or stake proxy UTXOs found, waiting for 10 seconds...");
            await new Promise((resolve) => setTimeout(resolve, 10000));
            continue;
        }

        const stakePoolUtxo = validStakePoolUtxos[0];
        const stakeProxyUtxo = validStakeProxyUtxos[0];
        const stakeOrderDatum = Data.from(stakeProxyUtxo.datum!, StakePoolProxyDatum);
        const stakePoolDatum = Data.from(stakePoolUtxo.datum!, StakePoolDatum);
        const poolAmount = stakePoolUtxo.assets[subject];
        const stakeAmount = stakeProxyUtxo.assets[subject];
        const lockedTotal = stakeAmount * (100n + stakeOrderDatum.reward_percentage) / 100n;
        const reward = lockedTotal - stakeAmount;
        const newStakePoolAmount = poolAmount - reward;

        console.log("Pool Amount", poolAmount);
        console.log("Stake Amount", stakeAmount);
        console.log("Amount to lock", lockedTotal);
        console.log("Reward", reward);
        console.log("New Pool Amount", newStakePoolAmount);

        const currentTime = lucid.utils.slotToUnixTime(lucid.currentSlot() - 100); // Why -100? Because of the time it takes to create the transaction?
        const locked_until = BigInt(currentTime) + BigInt(3_600_000) + BigInt(3_600_000) * stakeOrderDatum.days_locked;
        const laterTime = BigInt(new Date(currentTime + 2 * 60 * 60 * 1000).getTime());
        const asset_name = Data.to(laterTime) + fromText(stakePoolUtxo.outputIndex.toString()) + toHex(fromHex(stakePoolUtxo.txHash).slice(0, 17));
        console.log(Data.to(laterTime));
        console.log(fromText(stakePoolUtxo.outputIndex.toString()));
        console.log(toHex(fromHex(stakePoolUtxo.txHash).slice(0, 17)));
        const stake_key = stake_key_prefix + asset_name;
        const reference = reference_prefix + asset_name;
        console.log({ asset_name, stake_key, reference });
        const timeLockDatum: TimeLockDatum = {
            metadata: new Map([
                [fromText("name"), fromText("Stake Key ") + fromText(abbreviatedAmount(lockedTotal, 0n)) + fromText(" ") + stakePoolDatum.asset_name + fromText(" - ") + fromText(timeToDatestring(locked_until))],
                [fromText("image"), fromText("helloworld")],
                [fromText("locked_amount"), fromText(lockedTotal.toString())],
            ]),
            version: 1n,
            extra: {
                lock_until: locked_until,
                time_lock_key: stake_key,
            }
        };
        const lockDatum: TimeLockMetadata = new Map([
            [fromText("name"), fromText("test")]
        ]);
        console.log(timeToDatestring(1703851519000n));
        console.log(abbreviatedAmount(lockedTotal, 0n), lockedTotal);
        console.log(fromText("Stake Key ") + fromText(abbreviatedAmount(lockedTotal, 0n)) + fromText(" ") + stakePoolDatum.asset_name + fromText(" - ") + fromText(timeToDatestring(locked_until)));
        console.log(fromText(BigInt(1010000).toString()));
        console.log(Data.to(lockDatum, TimeLockMetadata));
        console.log(Data.to(timeLockDatum, TimeLockDatum));
        break;
        // const timeLockDatum = Data.to(
        //     {
        //         lock_until: locked_until,
        //         time_lock_key: stake_key,
        //     },
        //     TimeLockDatum
        // );

        // const stakePoolRedeemer = Data.to(
        //     {
        //         reward_index: BigInt(0),
        //     },
        //     StakePoolRedeemer
        // );

        // const stakeKeyRedeemer = Data.to(
        //     {
        //         stake_pool_index: BigInt(0),
        //         stake_proxy_index: BigInt(1),
        //         time_lock_index: BigInt(0),
        //     },
        //     StakeKeyMintRedeemer
        // );

        // const tx = await bLucid
        //     .newTx()
        //     .collectFrom([stakePoolUtxo], stakePoolRedeemer)
        //     .collectFrom([stakeProxyUtxo], Data.void())
        //     .addSigner(bWalletAddress)
        //     .validFrom(currentTime)
        //     .validTo(laterTime)
        //     .mintAssets({ [stake_key]: 1n }, stakeKeyRedeemer)
        //     .attachSpendingValidator(stakingValidatorScript)
        //     .attachSpendingValidator(stakingProxyValidatorScript)
        //     .attachMintingPolicy(stakingMintPolicy)
        //     .payToContract(stakingValidatorAddress, { inline: stakePoolUtxo.datum! }, { "lovelace": stakePoolUtxo.assets["lovelace"], [subject]: newStakePoolAmount })
        //     .payToContract(timeLockValidatorAddress, { inline: timeLockDatum }, { "lovelace": 2000000n, [subject]: lockedTotal })
        //     .payToAddress(lucid.utils.credentialToAddress(lucid.utils.keyHashToCredential(stakeOrderDatum.owner)), { [stake_key]: 1n })
        //     .complete();

        // const signedTx = await tx.sign().complete();
        // const txHash = await signedTx.submit();
        // console.log(`Execute stake ${txHash}, waiting for confirmation...`);
        // await lucid.provider.awaitTx(txHash);
        // console.log("Execute stake complete");
    }
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
