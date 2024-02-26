use aiken/bytearray.{concat, drop, from_string, take}
use aiken/cbor.{serialise}
use aiken/dict
use aiken/hash.{blake2b_256}
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list.{at, filter, find}
use aiken/math/rational
use aiken/string
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, ScriptContext, Transaction,
  TransactionId,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{
  add, flatten, from_lovelace, from_minted_value, quantity_of, to_minted_value,
  zero,
}
use staking_contracts/datums.{
  LockDatum, RewardSetting, StakePoolDatum, TimeLockDatum, reference_prefix,
  stake_nft_prefix, to_stake_pool_datum, to_time_lock_datum,
}
use staking_contracts/utils.{hour_millis, must_start_after, time_to_date_string}
use sundae/multisig.{Signature}

// Spec 2.4
pub type StakeNFTMintRedeemer {
  // Spec 2.4.1
  stake_pool_index: Int,
  // Spec 2.4.2
  time_lock_index: Int,
  // Spec 2.4.3
  mint: Bool,
}

// Spec 2.5
pub fn mint_transaction(
  redeemer: StakeNFTMintRedeemer,
  ctx: ScriptContext,
  time_lock_hash: ByteArray,
) -> Bool {
  when ctx.purpose is {
    // Spec 2.5.2
    Mint(own_policy) -> {
      //Retrieve all minted assets into an array
      let minted = from_minted_value(ctx.transaction.mint) |> flatten()

      //Only 2 assets minted
      // Spec 2.5.3
      expect 2 == list.length(minted)

      //Look for the reference nft (CIP-68)
      // Spec 2.5.4 - "exactly one token"
      expect [reference_nft] =
        // Spec 2.5.4 - "being minted"
        minted
          // Spec 2.5.4 - "with"
          |> filter(
               fn(mt) {
                 // Spec 2.5.4 - "a policy ID of Stake NFT"
                 mt.1st == own_policy &&
                 // Spec 2.5.4 - "and an asset name prefixed by"
                 take(mt.2nd, 4) == reference_prefix
               },
             )

      //Look for the stake nft (CIP-68)
      //  Spec 2.5.5 - "exactly one token"
      expect [stake_nft] =
        // Spec 2.5.5 - "being minted"
        minted
          // Spec 2.5.5 - "with"
          |> filter(
               fn(mt) {
                 // Spec 2.5.5 - "a policy ID of Stake NFT"
                 mt.1st == own_policy &&
                 // Spec 2.5.5 - "and an asset name prefixed by"
                 take(mt.2nd, 4) == stake_nft_prefix
               },
             )

      //Asset name without CIP-68 prefix
      // Spec 2.5.6
      let asset_name = drop(reference_nft.2nd, 4)

      //Ensure the stake nft has the same asset name as the reference nft
      // Spec 2.5.7 - n.b. included in the `and` condition below
      let correct_stake_nft_name = drop(stake_nft.2nd, 4) == asset_name

      //only one reference nft minted
      // Spec 2.5.8
      expect 1 == reference_nft.3rd
      //only one stake nft minted
      // Spec 2.5.8
      expect 1 == stake_nft.3rd

      //The stake pool input
      // Spec 2.5.9
      expect Some(stake_pool_input) =
        ctx.transaction.inputs |> at(redeemer.stake_pool_index)

      // Spec 2.5.10 - n.b. stake_pool_cred checked below
      expect ScriptCredential(stake_pool_cred) =
        stake_pool_input.output.address.payment_credential

      //The time lock output
      // Spec 2.5.11
      expect Some(time_lock_output) =
        ctx.transaction.outputs |> at(redeemer.time_lock_index)

      // Spec 2.5.12 - n.b. time_lock_cred checked below
      expect ScriptCredential(time_lock_cred) =
        time_lock_output.address.payment_credential

      //Fetch inlinedatum from stakepool input and cast to StakePoolDatum
      // Spec 2.5.13
      expect InlineDatum(stake_pool_input_datum) = stake_pool_input.output.datum
      let stake_pool_datum = to_stake_pool_datum(stake_pool_input_datum)

      //Fetch inlinedatum from timelock output and cast to TimeLockDatum
      // Spec 2.5.14
      expect InlineDatum(time_lock_output_datum) = time_lock_output.datum
      let time_lock_datum = to_time_lock_datum(time_lock_output_datum)

      //The amount of tokens to be locked (no decimals taken into account)
      // Spec 2.5.15
      let raw_amount =
        time_lock_output.value
          |> quantity_of(stake_pool_datum.policy_id, stake_pool_datum.asset_name)

      // Spec 2.5.16 - n.b. actually checked below in the `and` condition
      let reference_nft_in_time_lock =
        1 == quantity_of(time_lock_output.value, own_policy, reference_nft.2nd)

      //Construct the proper asset name using the unique components
      // Spec 2.5.17 - "let proper_asset_name" be
      let proper_asset_name =
        // Spec 2.5.17 - "the blake2b_256 hash of"
        blake2b_256(
          // Spec 2.5.17 - "the serialized"
          serialise(
            // Spec 2.5.17 - "stake_pool_input.output_reference"
            stake_pool_input.output_reference
          )
        )
        // Spec 2.5.17 - The first 28 bytes of
        |> take(28)

      //Construct the proper metadata nft name
      // Spec 2.5.18 - "let proper_meta_name be"
      let proper_meta_name =
        list.foldl(
          [
            // Spec 2.5.18 - Stake NFT
            "Stake NFT ",
            // Spec 2.5.18 - "the reward token asset name"
            stake_pool_datum.asset_name,
            // Spec 2.5.18 - a dash
            " - ",
            // Spec 2.5.18 - and some human readable expression of lock_until
            // n.b. the details of this method are not audited, but the impact is low
            time_to_date_string(time_lock_datum.extra.lock_until),
          ],
          "",
          // Spec 2.5.18 - "The concatenation of"
          fn(el, sum) { bytearray.concat(sum, el) },
        )

      //Validations
      //Make sure the asset name is as expected
      // Spec 2.5.19 - n.b. included in the `and` condition below
      let correct_reference_name = asset_name == proper_asset_name

      // Spec 2.5.20 - n.b. included in the `and` condition below
      let correct_stake_nft_set =
        time_lock_datum.extra.time_lock_nft == bytearray.concat(
          own_policy,
          stake_nft.2nd,
        )

      //Ensure the metadata token name is as expected
      // Spec 2.5.21 - n.b. included in the `and` condition below
      let correct_meta_name =
        dict.get(time_lock_datum.metadata, "name") == Some(proper_meta_name)

      //Make sure an extra field is present in the metadata showing the tokens locked by the nft
      // Spec 2.5.22
      let proper_meta_amount =
        list.foldl(
          [
            // Spec 2.5.22 - `[(`
            "[",
            "(",
            // Spec 2.5.22 - The reward token policy ID
            bytearray.from_string(bytearray.to_hex(stake_pool_datum.policy_id)),
            // Spec 2.5.22 - `,`
            ",",
            // Spec 2.5.22 - The reward token asset name
            bytearray.from_string(bytearray.to_hex(stake_pool_datum.asset_name)),
            // Spec 2.5.22 - `,`
            ",",
            // Spec 2.5.22 - `raw_amount`
            bytearray.from_string(string.from_int(raw_amount)),
            // Spec 2.5.22 - `)]`
            ")",
            "]",
          ],
          "",
          // Spec 2.5.22 "the concatenation of"
          fn(el, sum) { bytearray.concat(sum, el) },
        )
      // Spec 2.5.22 - n.b. included in the `and` condition below
      let correct_meta_amount =
        // Spec 2.5.22 - The CIP-68 metadata at "locked_amount" must be
        dict.get(time_lock_datum.metadata, "locked_assets") == Some(
          proper_meta_amount,
        )

      //Verify script hashes
      // Spec 2.5.10 - n.b. stake_pool_cred comes from stake_pool_input, and this is included in the `and` below
      let correct_stake_pool = own_policy == stake_pool_cred
      // Spec 2.5.12 - n.b. time_lock_cred comes from time_lock_output, and this is included in the `and` below
      let correct_time_lock = time_lock_hash == time_lock_cred

      and {
        // Spec 2.5.16
        reference_nft_in_time_lock?,
        // Spec 2.5.20
        correct_stake_nft_set?,
        // Spec 2.5.7
        correct_stake_nft_name?,
        // Spec 2.5.19
        correct_reference_name?,
        // Spec 2.5.21
        correct_meta_name?,
        // Spec 2.5.22
        correct_meta_amount?,
        // Spec 2.5.10
        correct_stake_pool?,
        // Spec 2.5.12
        correct_time_lock?,
      }
    }
    _ -> False
  }
}

// Spec 2.6
pub fn burn_transaction(ctx: ScriptContext, time_lock_hash: ByteArray) -> Bool {
  when ctx.purpose is {
    // Spec 2.6.2
    Mint(own_policy) -> {
      //Retrieve all minted assets into an array
      // Spec 2.6.3
      let burned = from_minted_value(ctx.transaction.mint) |> flatten()
      //Look for the reference nfts (CIP-68)
      // Spec 2.6.5
      let reference_nfts =
        burned
          |> filter(
               fn(mt) {
                 mt.1st == own_policy && take(mt.2nd, 4) == reference_prefix
               },
             )
      // Spec 2.6.4
      let burned_count = list.length(burned)
      //Look for the stake nft (CIP-68)
      // Spec 2.6.6
      let stake_nfts =
        burned
          |> filter(
               fn(mt) {
                 mt.1st == own_policy && take(mt.2nd, 4) == stake_nft_prefix
               },
             )

      // Spec 2.6.7
      let nft_count = list.length(reference_nfts) + list.length(stake_nfts)

      //Ensure that only CIP-68 nft's are burned
      // Spec 2.6.7 - n.b. included in the `and` condition below
      let correct_number_burned = burned_count == nft_count

      // Spec 2.6.8
      let correct_burns =
        // Spec 2.6.8 - "For each asset"
        list.all(
          // Spec 2.6.8 - "in reference_nfts"
          reference_nfts,
          fn(reference_nft) {
            //Asset name without CIP-68 prefix
            // Spec 2.6.8.1
            let asset_name = drop(reference_nft.2nd, 4)

            // Spec 2.6.8.2
            expect Some(stake_nft) =
              stake_nfts |> find(fn(sk) { drop(sk.2nd, 4) == asset_name })

            when reference_nft.3rd is {
              //Burn scenario (unlock of locked tokens)
              // Spec 2.6.8.3 - n.b. any other case is immediately False
              -1 -> {
                //Full asset unit
                // Used in Spec 2.6.8.7
                let burned_unit = bytearray.concat(stake_nft.1st, stake_nft.2nd)
                //The time lock input that contains the reference nft
                // Spec 2.6.8.5 - "There must be", "Let this input be the time_lock_input"
                expect Some(time_lock_input) =
                  // Spec 2.6.8.5 - "input"
                  ctx.transaction.inputs
                  // Spec 2.6.8.5 - "at least one"
                    |> find(
                         fn(i) {
                          // Spec 2.6.8.5 - "with the time_lock_hash script credential"
                           i.output.address.payment_credential == ScriptCredential(
                             time_lock_hash,
                             // Spec 2.6.8.5 - "with the reference NFT in the value"
                           ) && quantity_of(
                             i.output.value,
                             reference_nft.1st,
                             reference_nft.2nd,
                           ) == 1
                         },
                       )

                //The inline datum belonging to the time lock inptu cast to TimeLockDatum
                // Spec 2.6.8.6
                expect InlineDatum(time_lock_input_datum) =
                  time_lock_input.output.datum
                let time_lock_datum = to_time_lock_datum(time_lock_input_datum)

                //Ensure the tokens burned match the timelock nft
                // Spec 2.6.8.7 - n.b. included in the `and` condition below
                let correct_token_burned =
                  time_lock_datum.extra.time_lock_nft == burned_unit

                //Make sure both tokens are burned
                // Spec 2.6.8.4 - n.b. equivalent to checking that stake_nft.3rd is equal to -1
                let both_burned = stake_nft.3rd == reference_nft.3rd
                and {
                  // Spec 2.6.8.8
                  must_start_after(
                    ctx.transaction.validity_range,
                    time_lock_datum.extra.lock_until,
                  )?,
                  // Spec 2.6.8.7
                  correct_token_burned?,
                  // 2.6.8.4
                  both_burned?,
                }
              }
              // Spec 2.6.8.3
              _ -> False
            }
          },
        )
      and {
        // Spec 2.6.7
        correct_number_burned?,
        // Spec 2.6.8
        correct_burns?,
      }
    }
    _ -> False
  }
}

test mint_transaction_lock() {
  let current_time = 0

  let time_lock_hash =
    #"550cc5a9682bcbbe5583f1006624000032b4d8f4ddd6f37623462ff9"

  let stake_pool_hash =
    #"00000000000000000000000000000000000000000000000000000011"

  expect Some(reward) = rational.new(1, 100)

  let stake_pool_datum =
    StakePoolDatum {
      owner: Signature(
        #"00000000000000000000000000000000000000000000000000000000",
      ),
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      reward_settings: [
        RewardSetting { ms_locked: 86_400_000, reward_multiplier: reward },
      ],
      open_time: 0,
    }
  let stake_pool_output_reference =
    OutputReference {
      transaction_id: TransactionId(
        #"00000000000000000000000000000000000000000000000000000000",
      ),
      output_index: 0,
    }
  let stake_pool_output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(stake_pool_hash),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_000_000_000,
           ),
      datum: InlineDatum(stake_pool_datum),
      reference_script: None,
    }

  let stake_pool_input =
    Input {
      output_reference: stake_pool_output_reference,
      output: stake_pool_output,
    }

  let asset_name =
    blake2b_256(serialise(stake_pool_output_reference)) |> take(28)
  let stake_nft = concat(stake_nft_prefix, asset_name)
  let reference_nft = concat(reference_prefix, asset_name)

  let meta_name =
    list.foldl(
      [
        "Stake NFT ",
        #"000000000000",
        " - ",
        time_to_date_string(current_time + hour_millis + 86_400_000),
      ],
      "",
      fn(el, sum) { bytearray.concat(sum, el) },
    )

  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new()
        |> dict.insert("name", meta_name, bytearray.compare)
        |> dict.insert(
             "image",
             "https://my-stake-nft-img.com/img.png",
             bytearray.compare,
           )
        |> dict.insert(
             "locked_assets",
             list.foldl(
               [
                 "[",
                 "(",
                 bytearray.from_string(
                   bytearray.to_hex(stake_pool_datum.policy_id),
                 ),
                 ",",
                 bytearray.from_string(
                   bytearray.to_hex(stake_pool_datum.asset_name),
                 ),
                 ",",
                 bytearray.from_string(string.from_int(1_010_000)),
                 ")",
                 "]",
               ],
               "",
               fn(el, sum) { bytearray.concat(sum, el) },
             ),
             bytearray.compare,
           ),
      version: 1,
      extra: LockDatum {
        lock_until: current_time + hour_millis + 86_400_000,
        time_lock_nft: bytearray.concat(
          #"00000000000000000000000000000000000000000000000000000011",
          stake_nft,
        ),
      },
    }

  let time_lock_data: Data = time_lock_datum
  let time_lock_output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(time_lock_hash),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_010_000,
           )
        |> add(
             #"00000000000000000000000000000000000000000000000000000011",
             reference_nft,
             1,
           ),
      datum: InlineDatum(time_lock_data),
      reference_script: None,
    }

  let stake_nft_mint_redeemer =
    StakeNFTMintRedeemer { stake_pool_index: 0, time_lock_index: 0, mint: True }
  let context =
    ScriptContext {
      purpose: Mint(#"00000000000000000000000000000000000000000000000000000011"),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction {
               ..transaction,
               inputs: [stake_pool_input],
               outputs: [time_lock_output],
               mint: zero()
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      stake_nft,
                      1,
                    )
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      reference_nft,
                      1,
                    )
                 |> to_minted_value(),
               validity_range: Interval {
                 lower_bound: IntervalBound {
                   bound_type: Finite(0),
                   is_inclusive: True,
                 },
                 upper_bound: IntervalBound {
                   bound_type: Finite(3_600_000),
                   is_inclusive: True,
                 },
               },
             }
           },
    }
  mint_transaction(stake_nft_mint_redeemer, context, time_lock_hash)
}

test burn_transaction_single_unlock() {
  let current_time = 2 * 86_400_000

  let time_lock_hash =
    #"550cc5a9682bcbbe5583f1006624000032b4d8f4ddd6f37623462ff9"

  let asset_name =
    list.foldl(
      [
        serialise(3_600_000),
        from_string(@"0"),
        #"00000000000000000000000000000000000000000000000000000000" |> take(17),
      ],
      "",
      fn(el, sum) { bytearray.concat(sum, el) },
    )

  let stake_nft = concat(stake_nft_prefix, asset_name)
  let reference_nft = concat(reference_prefix, asset_name)

  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum {
        lock_until: hour_millis + 86_400_000,
        time_lock_nft: concat(
          #"00000000000000000000000000000000000000000000000000000011",
          stake_nft,
        ),
      },
    }

  let time_lock_data: Data = time_lock_datum
  let time_lock_output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(time_lock_hash),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_010_000,
           )
        |> add(
             #"00000000000000000000000000000000000000000000000000000011",
             reference_nft,
             1,
           ),
      datum: InlineDatum(time_lock_data),
      reference_script: None,
    }
  let time_lock_output_reference =
    OutputReference { transaction_id: TransactionId(""), output_index: 1 }

  let time_lock_input =
    Input {
      output_reference: time_lock_output_reference,
      output: time_lock_output,
    }
  let context =
    ScriptContext {
      purpose: Mint(#"00000000000000000000000000000000000000000000000000000011"),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction {
               ..transaction,
               inputs: [time_lock_input],
               outputs: [],
               mint: zero()
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      stake_nft,
                      -1,
                    )
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      reference_nft,
                      -1,
                    )
                 |> to_minted_value(),
               validity_range: Interval {
                 lower_bound: IntervalBound {
                   bound_type: Finite(current_time),
                   is_inclusive: True,
                 },
                 upper_bound: IntervalBound {
                   bound_type: Finite(current_time + 3_600_000),
                   is_inclusive: True,
                 },
               },
             }
           },
    }

  burn_transaction(context, time_lock_hash)
}

test burn_transaction_multi_unlock() {
  let current_time = 2 * 86_400_000

  let time_lock_hash =
    #"550cc5a9682bcbbe5583f1006624000032b4d8f4ddd6f37623462ff9"

  let asset_name_1 =
    list.foldl(
      [
        serialise(3_600_000),
        from_string(@"0"),
        #"00000000000000000000000000000000000000000000000000000000" |> take(17),
      ],
      "",
      fn(el, sum) { bytearray.concat(sum, el) },
    )

  let stake_nft_1 = concat(stake_nft_prefix, asset_name_1)
  let reference_nft_1 = concat(reference_prefix, asset_name_1)

  let asset_name_2 =
    list.foldl(
      [
        serialise(3_600_000),
        from_string(@"0"),
        #"11000000000000000000000000000000000000000000000000000000" |> take(17),
      ],
      "",
      fn(el, sum) { bytearray.concat(sum, el) },
    )

  let stake_nft_2 = concat(stake_nft_prefix, asset_name_2)
  let reference_nft_2 = concat(reference_prefix, asset_name_2)

  let time_lock_datum_1 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum {
        lock_until: hour_millis + 86_400_000,
        time_lock_nft: concat(
          #"00000000000000000000000000000000000000000000000000000011",
          stake_nft_1,
        ),
      },
    }

  let time_lock_data_1: Data = time_lock_datum_1
  let time_lock_output_1 =
    Output {
      address: Address {
        payment_credential: ScriptCredential(time_lock_hash),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_010_000,
           )
        |> add(
             #"00000000000000000000000000000000000000000000000000000011",
             reference_nft_1,
             1,
           ),
      datum: InlineDatum(time_lock_data_1),
      reference_script: None,
    }
  let time_lock_output_reference_1 =
    OutputReference { transaction_id: TransactionId(""), output_index: 1 }

  let time_lock_input_1 =
    Input {
      output_reference: time_lock_output_reference_1,
      output: time_lock_output_1,
    }

  let time_lock_datum_2 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum {
        lock_until: hour_millis + 86_400_000,
        time_lock_nft: concat(
          #"00000000000000000000000000000000000000000000000000000011",
          stake_nft_2,
        ),
      },
    }

  let time_lock_data_2: Data = time_lock_datum_2
  let time_lock_output_2 =
    Output {
      address: Address {
        payment_credential: ScriptCredential(time_lock_hash),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_010_000,
           )
        |> add(
             #"00000000000000000000000000000000000000000000000000000011",
             reference_nft_2,
             1,
           ),
      datum: InlineDatum(time_lock_data_2),
      reference_script: None,
    }
  let time_lock_output_reference_2 =
    OutputReference { transaction_id: TransactionId(""), output_index: 2 }

  let time_lock_input_2 =
    Input {
      output_reference: time_lock_output_reference_2,
      output: time_lock_output_2,
    }
  let context =
    ScriptContext {
      purpose: Mint(#"00000000000000000000000000000000000000000000000000000011"),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction {
               ..transaction,
               inputs: [time_lock_input_1, time_lock_input_2],
               outputs: [],
               mint: zero()
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      stake_nft_1,
                      -1,
                    )
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      reference_nft_1,
                      -1,
                    )
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      stake_nft_2,
                      -1,
                    )
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      reference_nft_2,
                      -1,
                    )
                 |> to_minted_value(),
               validity_range: Interval {
                 lower_bound: IntervalBound {
                   bound_type: Finite(current_time),
                   is_inclusive: True,
                 },
                 upper_bound: IntervalBound {
                   bound_type: Finite(current_time + 3_600_000),
                   is_inclusive: True,
                 },
               },
             }
           },
    }

  burn_transaction(context, time_lock_hash)
}
