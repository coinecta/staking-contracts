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

pub type StakeNFTMintRedeemer {
  stake_pool_index: Int,
  time_lock_index: Int,
  mint: Bool,
}

pub fn mint_transaction(
  redeemer: StakeNFTMintRedeemer,
  ctx: ScriptContext,
  time_lock_hash: ByteArray,
) -> Bool {
  when ctx.purpose is {
    Mint(own_policy) -> {
      //Retrieve all minted assets into an array
      let minted = from_minted_value(ctx.transaction.mint) |> flatten()

      //Only 2 assets minted
      expect 2 == list.length(minted)
      //Look for the reference nft (CIP-68)
      expect [reference_nft] =
        minted
          |> filter(
               fn(mt) {
                 mt.1st == own_policy && take(mt.2nd, 4) == reference_prefix
               },
             )

      //Look for the stake nft (CIP-68)
      expect [stake_nft] =
        minted
          |> filter(
               fn(mt) {
                 mt.1st == own_policy && take(mt.2nd, 4) == stake_nft_prefix
               },
             )

      //Asset name without CIP-68 prefix
      let asset_name = drop(reference_nft.2nd, 4)

      //Ensure the stake nft has the same asset name as the reference nft
      let correct_stake_nft_name = drop(stake_nft.2nd, 4) == asset_name

      //only one reference nft minted
      expect 1 == reference_nft.3rd
      //only one stake nft minted
      expect 1 == stake_nft.3rd
      //The stake pool input
      expect Some(stake_pool_input) =
        ctx.transaction.inputs |> at(redeemer.stake_pool_index)
      expect ScriptCredential(stake_pool_cred) =
        stake_pool_input.output.address.payment_credential
      //The time lock output
      expect Some(time_lock_output) =
        ctx.transaction.outputs |> at(redeemer.time_lock_index)
      expect ScriptCredential(time_lock_cred) =
        time_lock_output.address.payment_credential
      //Fetch inlinedatum from stakepool input and cast to StakePoolDatum
      expect InlineDatum(stake_pool_input_datum) = stake_pool_input.output.datum
      let stake_pool_datum = to_stake_pool_datum(stake_pool_input_datum)

      //Fetch inlinedatum from timelock output and cast to TimeLockDatum
      expect InlineDatum(time_lock_output_datum) = time_lock_output.datum
      let time_lock_datum = to_time_lock_datum(time_lock_output_datum)

      //The amount of tokens to be locked (no decimals taken into account)
      let raw_amount =
        time_lock_output.value
          |> quantity_of(stake_pool_datum.policy_id, stake_pool_datum.asset_name)

      let reference_nft_in_time_lock =
        1 == quantity_of(time_lock_output.value, own_policy, reference_nft.2nd)

      //Construct the proper asset name using the unique components
      let proper_asset_name =
        blake2b_256(serialise(stake_pool_input.output_reference))
          |> take(28)

      //Construct the proper metadata nft name
      let proper_meta_name =
        list.foldl(
          [
            "Stake NFT ",
            stake_pool_datum.asset_name,
            " - ",
            time_to_date_string(time_lock_datum.extra.lock_until),
          ],
          "",
          fn(el, sum) { bytearray.concat(sum, el) },
        )

      //Validations
      //Make sure the asset name is as expected
      let correct_reference_name = asset_name == proper_asset_name

      let correct_stake_nft_set =
        time_lock_datum.extra.time_lock_nft == bytearray.concat(
          own_policy,
          stake_nft.2nd,
        )

      //Ensure the metadata token name is as expected
      let correct_meta_name =
        dict.get(time_lock_datum.metadata, "name") == Some(proper_meta_name)

      //Make sure an extra field is present in the metadata showing the tokens locked by the nft
      let proper_meta_amount =
        list.foldl(
          [
            "[",
            "(",
            bytearray.from_string(bytearray.to_hex(stake_pool_datum.policy_id)),
            ",",
            bytearray.from_string(bytearray.to_hex(stake_pool_datum.asset_name)),
            ",",
            bytearray.from_string(string.from_int(raw_amount)),
            ")",
            "]",
          ],
          "",
          fn(el, sum) { bytearray.concat(sum, el) },
        )
      let correct_meta_amount =
        dict.get(time_lock_datum.metadata, "locked_assets") == Some(
          proper_meta_amount,
        )

      //Verify script hashes
      let correct_stake_pool = own_policy == stake_pool_cred
      let correct_time_lock = time_lock_hash == time_lock_cred

      and {
        reference_nft_in_time_lock?,
        correct_stake_nft_set?,
        correct_stake_nft_name?,
        correct_reference_name?,
        correct_meta_name?,
        correct_meta_amount?,
        correct_stake_pool?,
        correct_time_lock?,
      }
    }
    _ -> False
  }
}

pub fn burn_transaction(ctx: ScriptContext, time_lock_hash: ByteArray) -> Bool {
  when ctx.purpose is {
    Mint(own_policy) -> {
      //Retrieve all minted assets into an array
      let burned = from_minted_value(ctx.transaction.mint) |> flatten()
      //Look for the reference nfts (CIP-68)
      let reference_nfts =
        burned
          |> filter(
               fn(mt) {
                 mt.1st == own_policy && take(mt.2nd, 4) == reference_prefix
               },
             )
      let burned_count = list.length(burned)
      //Look for the stake nft (CIP-68)
      let stake_nfts =
        burned
          |> filter(
               fn(mt) {
                 mt.1st == own_policy && take(mt.2nd, 4) == stake_nft_prefix
               },
             )

      let nft_count = list.length(reference_nfts) + list.length(stake_nfts)

      //Ensure that only CIP-68 nft's are burned
      let correct_number_burned = burned_count == nft_count

      let correct_burns =
        list.all(
          reference_nfts,
          fn(reference_nft) {
            //Asset name without CIP-68 prefix
            let asset_name = drop(reference_nft.2nd, 4)

            expect Some(stake_nft) =
              stake_nfts |> find(fn(sk) { drop(sk.2nd, 4) == asset_name })

            when reference_nft.3rd is {
              //Burn scenario (unlock of locked tokens)
              -1 -> {
                //Full asset unit
                let burned_unit = bytearray.concat(stake_nft.1st, stake_nft.2nd)
                //The time lock input that contains the reference nft
                expect Some(time_lock_input) =
                  ctx.transaction.inputs
                    |> find(
                         fn(i) {
                           i.output.address.payment_credential == ScriptCredential(
                             time_lock_hash,
                           ) && quantity_of(
                             i.output.value,
                             reference_nft.1st,
                             reference_nft.2nd,
                           ) == 1
                         },
                       )

                //The inline datum belonging to the time lock inptu cast to TimeLockDatum
                expect InlineDatum(time_lock_input_datum) =
                  time_lock_input.output.datum
                let time_lock_datum = to_time_lock_datum(time_lock_input_datum)

                //Ensure the tokens burned match the timelock nft
                let correct_token_burned =
                  time_lock_datum.extra.time_lock_nft == burned_unit

                //Make sure both tokens are burned
                let both_burned = stake_nft.3rd == reference_nft.3rd
                and {
                  must_start_after(
                    ctx.transaction.validity_range,
                    time_lock_datum.extra.lock_until,
                  )?,
                  correct_token_burned?,
                  both_burned?,
                }
              }
              _ -> False
            }
          },
        )
      and {
        correct_number_burned?,
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
