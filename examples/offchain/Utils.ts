import { Rational } from "./Datums.ts";

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