import { Credential, Data, Lucid, Script, UTxO } from "https://deno.land/x/lucid@0.10.7/mod.ts";
import { Rational } from "./Datums.ts";


export const abbreviatedAmount = (amount: bigint, decimals: bigint): string => {
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

export const timeToDatestring = (time: bigint): string => {
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


export function add_reward(amount: bigint, reward: Rational): bigint {
    const amountRational = Rational.fromInt(amount);
    const oneRational = Rational.fromInt(1n);
    return amountRational.mul(oneRational.add(reward)).floor();
}

export function powBigInt(base: bigint, exponent: bigint): bigint {
    let result = 1n;
    for (let i = 0n; i < exponent; i++) {
        result *= base;
    }
    return result;
}

export function floorToSecond(time: number): number {
    return Math.floor(time / 1000) * 1000;
}

export const createScriptReferenceAsync = async (lucid: Lucid, validatorScript: Script, stakeCredential: Credential) => {
    const scriptAddr = lucid.utils.validatorToAddress(validatorScript, stakeCredential);
    console.log("Creating Script Reference", scriptAddr);

    const tx = await lucid.newTx()
        .payToContract(scriptAddr, {
            asHash: Data.void(),
            scriptRef: validatorScript,
        }, {})
        .complete();
    const signedTx = await tx.sign().complete();
    const txHash = await signedTx.submit();

    console.log("Created Script Reference, waiting for confirmation: ", txHash);

    await lucid.awaitTx(txHash);
    return { txHash, outputIndex: 0, address: scriptAddr } as UTxO;
}

export const exists = async (filename: string): Promise<boolean> => {
    try {
      await Deno.stat(filename);
      // successful, file or directory must exist
      return true;
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        // file or directory does not exist
        return false;
      } else {
        // unexpected error, maybe permissions, pass it along
        throw error;
      }
    }
  };