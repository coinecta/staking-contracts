import { Constr, Data } from "https://deno.land/x/lucid@0.10.7/mod.ts";

// Define a type for PosixTime
type PosixTime = bigint;

export interface CborSerializable {
    toData(): Data;
    fromData(data: Data): void;
}

export abstract class MultisigScript implements CborSerializable {
    abstract match<T>(matcher: MultisigScriptMatcher<T>): T;
    abstract toData(): Data;
    abstract fromData(data: Data): void;
}

export interface MultisigScriptMatcher<T> {
    Signature(key_hash: string): T;
    AllOf(scripts: MultisigScript[]): T;
    AnyOf(scripts: MultisigScript[]): T;
    AtLeast(required: bigint, scripts: MultisigScript[]): T;
    Before(time: PosixTime): T;
    After(time: PosixTime): T;
    Script(script_hash: string): T;
}

export class Signature extends MultisigScript {
    constructor(key_hash?: string) {
        super();
        this.key_hash = key_hash || "";
    }

    public key_hash = "";

    match<T>(matcher: MultisigScriptMatcher<T>): T {
        return matcher.Signature(this.key_hash);
    }

    toData = () => new Constr(0, [this.key_hash]);
    fromData(data: Data) {
        if (data instanceof Constr) {
            this.key_hash = data.fields[0] as string;
        } else {
            throw new Error("Invalid data format for Signature");
        }
    }
}

export class Rational implements CborSerializable {
    constructor(
        numerator?: bigint,
        denominator?: bigint,
    ) {
        this.numerator = numerator || 0n;
        this.denominator = denominator || 1n;
    }

    public numerator = 0n;
    public denominator = 1n;

    static fromInt(value: bigint): Rational {
        return new Rational(value, 1n);
    }

    add(other: Rational): Rational {
        if (this.denominator === other.denominator) {
            return new Rational(this.numerator + other.numerator, this.denominator);
        } else {
            return new Rational(
                this.numerator * other.denominator + other.numerator * this.denominator,
                this.denominator * other.denominator
            );
        }
    }

    mul(other: Rational): Rational {
        return new Rational(this.numerator * other.numerator, this.denominator * other.denominator);
    }

    floor(): bigint {
        return this.numerator / this.denominator;
    }

    toData = () => new Constr(0, [this.numerator, this.denominator]) as unknown as Data;
    fromData(data: Data) {
        if (data instanceof Constr) {
            this.numerator = BigInt(data.fields[0].toString())
            this.denominator = BigInt(data.fields[1].toString())
        } else {
            throw new Error("Invalid data format for Rational");
        }
    }
}

export class Credential implements CborSerializable {
    constructor(
        public hash?: string
    ) { }

    toData = () => new Constr(0, [this.hash]) as unknown as Data;
    fromData(data: Data) {
        if (data instanceof Constr) {
            this.hash = data.fields[0] as string;
        } else {
            throw new Error("Invalid data format for Credential");
        }
    }
}

export class Address implements CborSerializable {
    constructor(
        public payment_credential?: Credential,
        public stake_credential?: StakeCredential,
    ) { }

    toData = () => {
        if (this.stake_credential) {
            return new Constr(0, [
                this.payment_credential!.toData(), 
                new Constr(0, [this.stake_credential.toData()])
            ]) as unknown as Data;
        } else {
            return new Constr(0, [
                this.payment_credential!.toData(), new Constr(1, [])
            ]) as unknown as Data;
        }
    }

    fromData(data: Data) {
        if (data instanceof Constr) {
            if (data.fields.length == 1) {
                this.payment_credential = DataConvert.fromData(data.fields[0] as Data, Credential);
            } else if (data.fields.length == 2) {
                this.payment_credential = DataConvert.fromData(data.fields[0] as Data, Credential);
                this.stake_credential = DataConvert.fromData(data.fields[1] as Data, StakeCredential);
            } else {
                throw new Error("Invalid data format for Address");
            }
        } else {
            throw new Error("Invalid data format for Address");
        }
    }
}

export class StakeCredential implements CborSerializable {
    constructor(
        public credential?: Credential,
    ) { }

    toData = () => new Constr(0, [this.credential?.toData()]) as unknown as Data;
    fromData(data: Data) {
        if (data instanceof Constr) {
            this.credential = DataConvert.fromData((data.fields[0] as Constr<Data>).fields[0], Credential);
        } else {
            throw new Error("Invalid data format for StakeCredential");
        }
    }
}

export class NoDatum implements CborSerializable {
    toData = () => new Constr(0, []);
    fromData(data: Data) {
        if (data instanceof Constr) {
            if (data.fields.length != 0) {
                throw new Error("Invalid data format for NoDatum");
            }
        } else {
            throw new Error("Invalid data format for NoDatum");
        }
    }
}

export class DatumHash implements CborSerializable {
    constructor(public hash: string) {}  // Using string for simplicity

    toData = () => new Constr(1, [this.hash]);
    fromData(data: Data) {
        if (data instanceof Constr) {
            this.hash = data.fields[0] as string;
        } else {
            throw new Error("Invalid data format for DatumHash");
        }
    }
}

export class InlineDatum implements CborSerializable {
    constructor(public data: Data) {}

    toData = () => new Constr(2, [this.data]);
    fromData(data: Data) {
        if (data instanceof Constr) {
            this.data = data.fields[0] as Data;
        } else {
            throw new Error("Invalid data format for InlineDatum");
        }
    }
}

export type Datum = NoDatum | DatumHash | InlineDatum;

export class Destination implements CborSerializable {
    constructor(
        public address?: Address,
        public datum?: Datum,
    ) { }

    toData = () => {
        if (this.datum) {
            return new Constr(0, [this.address!.toData(), this.datum.toData()]) as unknown as Data;
        } else {
            return new Constr(0, [this.address!.toData(), new NoDatum().toData()]) as unknown as Data;
        }
    }

    fromData(data: Data) {
        if (data instanceof Constr) {
            this.address = DataConvert.fromData(data.fields[0] as Data, Address);
            if (data.fields.length === 2) {
                // Address and Datum are present
                const datumData = data.fields[1] as Data;
                if (datumData instanceof Constr) {
                    switch (datumData.index) {
                        case 0:
                            this.datum = new NoDatum();
                            break;
                        case 1:
                            this.datum = new DatumHash(datumData.fields[0] as string);
                            break;
                        case 2:
                            this.datum = new InlineDatum(datumData.fields[0] as Data);
                            break;
                        default:
                            throw new Error("Unknown Datum type");
                    }
                }
            } else {
                throw new Error("Invalid data format for Destination");
            }
        } else {
            throw new Error("Invalid data format for Destination");
        }
    }
}

export class DataConvert {
    static fromData<T extends CborSerializable>(data: Data, classRef: { new(): T }): T {
        const instance = new classRef();
        instance.fromData(data);
        return instance;
    }
}