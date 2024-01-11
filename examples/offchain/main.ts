import { Blockfrost, Data, Lucid, Network, Script, fromText } from "https://deno.land/x/lucid@0.10.7/mod.ts";
import { config } from "https://deno.land/x/dotenv@v3.2.2/mod.ts";

const env = config();
import stakingValidatorsBP from "../../plutus.json" assert { type: "json" };

const RewardSetting = Data.Object({
    days_locked: Data.Integer(),
    percentage_reward: Data.Integer(),
});
type RewardSetting = Data.Static<typeof RewardSetting>;

const StakePoolDatumSchema = Data.Object({
    time_lock_hash: Data.Bytes(),
    reward_settings: Data.Array(RewardSetting),
    policy_id: Data.Bytes(),
    asset_name: Data.Bytes(),
    owner: Data.Bytes(),
});
type StakePoolDatum = Data.Static<typeof StakePoolDatumSchema>;
const StakePoolDatum = StakePoolDatumSchema as unknown as StakePoolDatum;

const StakePoolProxyDatumSchema = Data.Object({
    owner: Data.Bytes(),
    days_locked: Data.Integer(),
    reward_percentage: Data.Integer(),
    time_lock_hash: Data.Bytes(),
    policy_id: Data.Bytes(),
    asset_name: Data.Bytes(),
    key_policy_id: Data.Bytes(),
});

type StakePoolProxyDatum = Data.Static<typeof StakePoolProxyDatumSchema>;
const StakePoolProxyDatum = StakePoolProxyDatumSchema as unknown as StakePoolProxyDatum;

const StakePoolRedeemerSchema = Data.Object({
    reward_index: Data.Integer()
});
type StakePoolRedeemer = Data.Static<typeof StakePoolRedeemerSchema>;
const StakePoolRedeemer = StakePoolRedeemerSchema as unknown as StakePoolRedeemer;

const TimeLockDatumSchema = Data.Object({
    lock_until: Data.Integer(),
    time_lock_key: Data.Bytes(),
});
type TimeLockDatum = Data.Static<typeof TimeLockDatumSchema>;
const TimeLockDatum = TimeLockDatumSchema as unknown as TimeLockDatum;

const StakeKeyMintRedeemerSchema = Data.Object({
    stake_pool_index: Data.Integer(),
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
        time_lock_hash: lucid.utils.validatorToScriptHash(timeLockValidatorScript),
        reward_settings: [
            {
                days_locked: 1n,
                percentage_reward: 1n,
            }
        ]
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
        time_lock_hash: lucid.utils.validatorToScriptHash(timeLockValidatorScript),
        key_policy_id: stakingMintPolicyId,
        days_locked: 1n,
        reward_percentage: 1n,
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
        .collectFrom([myUtxos[0]], Data.to({ reward_index: 0n }, StakePoolRedeemer))
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
        const poolDatum = Data.from(stakePoolUtxo.datum!, StakePoolDatum);
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
        const laterTime = new Date(currentTime + 2 * 60 * 60 * 1000).getTime();
        const stake_key =
            stakeOrderDatum.key_policy_id + fromText("s-") +
            stakeOrderDatum.asset_name.substring(0, 20) +
            fromText("-") + fromText(Math.floor(laterTime / 100000).toString()) +
            fromText(stakePoolUtxo.outputIndex.toString()) + fromText(stakePoolUtxo.txHash.substring(0, 6));
        console.log("Stake Key", stake_key);

        const timeLockDatum = Data.to(
            {
                lock_until: locked_until,
                time_lock_key: stake_key,
            },
            TimeLockDatum
        );

        const stakePoolRedeemer = Data.to(
            {
                reward_index: BigInt(0),
            },
            StakePoolRedeemer
        );

        const stakeKeyRedeemer = Data.to(
            {
                stake_pool_index: BigInt(0),
            },
            StakeKeyMintRedeemer
        );

        const tx = await bLucid
            .newTx()
            .collectFrom([stakePoolUtxo], stakePoolRedeemer)
            .collectFrom([stakeProxyUtxo], Data.void())
            .addSigner(bWalletAddress)
            .validFrom(currentTime)
            .validTo(laterTime)
            .mintAssets({ [stake_key]: 1n }, stakeKeyRedeemer)
            .attachSpendingValidator(stakingValidatorScript)
            .attachSpendingValidator(stakingProxyValidatorScript)
            .attachMintingPolicy(stakingMintPolicy)
            .payToContract(stakingValidatorAddress, { inline: stakePoolUtxo.datum! }, { "lovelace": stakePoolUtxo.assets["lovelace"], [subject]: newStakePoolAmount })
            .payToContract(timeLockValidatorAddress, { inline: timeLockDatum }, { "lovelace": 2000000n, [subject]: lockedTotal })
            .payToAddress(lucid.utils.credentialToAddress(lucid.utils.keyHashToCredential(stakeOrderDatum.owner)), { [stake_key]: 1n })
            .complete();

        const signedTx = await tx.sign().complete();
        const txHash = await signedTx.submit();
        console.log(`Execute stake ${txHash}, waiting for confirmation...`);
        await lucid.provider.awaitTx(txHash);
        console.log("Execute stake complete");
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