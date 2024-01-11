use aiken/bytearray.{concat, drop, from_string, take}
use aiken/cbor.{serialise}
use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list.{at, find, filter}
use aiken/math
use aiken/math/rational
use aiken/string
use aiken/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, ScriptContext,
  Transaction, TransactionId,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{
  add, flatten, from_lovelace, from_minted_value, quantity_of, to_minted_value,
  zero,
}
use staking_contracts/datums.{
  Destination, LockDatum, RewardSetting, StakePoolDatum, StakeProxyDatum,
  TimeLockDatum, reference_prefix, stake_key_prefix, to_stake_pool_datum,
  to_stake_proxy_datum, to_time_lock_datum,
}
use staking_contracts/utils.{
  abbreviated_amount, hour_millis, must_start_after, time_to_date_string,
}
use sundae/multisig.{Signature}

type StakeKeyMintRedeemer {
  stake_pool_index: Int,
  time_lock_index: Int,
  stake_proxy_index: Int,
}

validator(
  time_lock_hash: ByteArray,
  stake_pool_hash: ByteArray,
  stake_proxy_hash: ByteArray,
) {
  fn stake_key_mint(
    _datum: Void,
    redeemer: StakeKeyMintRedeemer,
    ctx: ScriptContext,
  ) {
    or {
      lock_transaction(
        redeemer,
        ctx,
        stake_pool_hash,
        stake_proxy_hash,
        time_lock_hash,
      )?,
      unlock_transaction(ctx, time_lock_hash)?,
    }
  }
}

fn lock_transaction(
  redeemer: StakeKeyMintRedeemer,
  ctx: ScriptContext,
  stake_pool_hash: ByteArray,
  stake_proxy_hash: ByteArray,
  time_lock_hash: ByteArray,
) -> Bool {
  when ctx.purpose is {
    Mint(_) -> {
      //Retrieve all minted assets into an array
      let minted = from_minted_value(ctx.transaction.mint) |> flatten()
      //Look for the reference nft (CIP-68)
      expect Some(reference_nft) =
        minted |> find(fn(mt) { take(mt.2nd, 4) == reference_prefix })

      //Look for the stake key (CIP-68)
      expect Some(stake_key) =
        minted |> find(fn(mt) { take(mt.2nd, 4) == stake_key_prefix })

      //Asset name without CIP-68 prefix
      let asset_name = drop(reference_nft.2nd, 4)

      //Ensure the stake key has the same asset name as the reference nft
      let correct_stake_key_name = drop(stake_key.2nd, 4) == asset_name

      when reference_nft.3rd is {
        //Mint scenario (tokens are to be locked)
        1 -> {
          //The stake pool input
          expect Some(stake_pool_input) =
            ctx.transaction.inputs |> at(redeemer.stake_pool_index)
          expect ScriptCredential(stake_pool_cred) =
            stake_pool_input.output.address.payment_credential
          //The stake proxy input
          expect Some(stake_proxy_input) =
            ctx.transaction.inputs |> at(redeemer.stake_proxy_index)
          expect ScriptCredential(stake_proxy_cred) =
            stake_proxy_input.output.address.payment_credential
          //The time lock output
          expect Some(time_lock_output) =
            ctx.transaction.outputs |> at(redeemer.time_lock_index)
          expect ScriptCredential(time_lock_cred) =
            time_lock_output.address.payment_credential

          //Fetch inlinedatum from stakepool input and cast to StakePoolDatum
          expect InlineDatum(stake_pool_input_datum) =
            stake_pool_input.output.datum
          let stake_pool_datum = to_stake_pool_datum(stake_pool_input_datum)

          //Fetch inlinedatum from stakeproxy input and cast to StakeProxyDatum
          expect InlineDatum(stake_proxy_input_datum) =
            stake_proxy_input.output.datum
          let stake_proxy_datum = to_stake_proxy_datum(stake_proxy_input_datum)

          //Fetch inlinedatum from timelock output and cast to TimeLockDatum
          expect InlineDatum(time_lock_output_datum) = time_lock_output.datum
          let time_lock_datum = to_time_lock_datum(time_lock_output_datum)

          //Fetch latest valid time for this transaction
          expect Finite(tx_latest_time) =
            ctx.transaction.validity_range.upper_bound.bound_type

          //We use the serialised time as part of the unique asset name
          let time_bytes = serialise(tx_latest_time)

          //The second part of the unique asset name is the output reference index+transaction id of the stake pool input
          let output_ref_index_bytes =
            bytearray.from_string(
              string.from_int(stake_pool_input.output_reference.output_index),
            )
          let TransactionId(stake_pool_input_transaction_id) =
            stake_pool_input.output_reference.transaction_id

          //The amount of tokens to be locked (no decimals taken into account)
          let raw_amount =
            time_lock_output.value
              |> quantity_of(
                   stake_pool_datum.policy_id,
                   stake_pool_datum.asset_name,
                 )

          //Amount with decimals, this is only to be used in metadata for the stake key
          let amount = raw_amount / math.pow(10, stake_pool_datum.decimals)

          //Construct the proper asset name using the unique components
          let proper_asset_name =
            list.foldl(
              [
                time_bytes,
                output_ref_index_bytes,
                stake_pool_input_transaction_id |> take(17),
              ],
              "",
              fn(el, sum) { bytearray.concat(sum, el) },
            )

          //Construct the proper metadata nft name
          let proper_meta_name =
            list.foldl(
              [
                "Stake Key ",
                abbreviated_amount(amount, 0),
                " ",
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

          //Only allow mint of 2 assets (reference and stake key)
          let no_extra_mint = list.length(minted) == 2

          //Ensure the metadata token name is as expected
          let correct_meta_name =
            dict.get(time_lock_datum.metadata, "name") == Some(proper_meta_name)

          //Ensure the token image is as requested by the user
          let correct_image =
            dict.get(time_lock_datum.metadata, "image") == Some(
              stake_proxy_datum.key_img_url,
            )

          //Make sure an extra field is present in the metadata showing the tokens locked by the key
          let correct_meta_amount =
            dict.get(time_lock_datum.metadata, "locked_amount") == Some(
              bytearray.from_string(string.from_int(amount)),
            )

          //Verify script hashes
          let correct_stake_pool = stake_pool_hash == stake_pool_cred
          let correct_stake_proxy = stake_proxy_hash == stake_proxy_cred
          let correct_time_lock = time_lock_hash == time_lock_cred

          and {
            correct_stake_key_name?,
            correct_reference_name?,
            no_extra_mint?,
            correct_meta_name?,
            correct_image?,
            correct_meta_amount?,
            correct_stake_pool?,
            correct_stake_proxy?,
            correct_time_lock?,
          }
        }
        _ -> False
      }
    }
    _ -> False
  }
}

fn unlock_transaction(
  ctx: ScriptContext,
  time_lock_hash: ByteArray,
) -> Bool {
  when ctx.purpose is {
    Mint(_policy_id) -> {
      //Retrieve all minted assets into an array
      let burned = from_minted_value(ctx.transaction.mint) |> flatten()
      //Look for the reference nfts (CIP-68)
      let reference_nfts =
        burned |> filter(fn(mt) { take(mt.2nd, 4) == reference_prefix })
      let burned_count = list.length(burned)
      //Look for the stake key (CIP-68)
      let stake_keys =
        burned |> filter(fn(mt) { take(mt.2nd, 4) == stake_key_prefix })

      let reference_nft_key_count = list.length(reference_nfts) + list.length(stake_keys)
      let correct_number_burned = burned_count == reference_nft_key_count

      let correct_burns = list.all(reference_nfts, fn(reference_nft) {
        //Asset name without CIP-68 prefix
      let asset_name = drop(reference_nft.2nd, 4)

      expect Some(stake_key) = stake_keys |> find(fn(sk) {drop(sk.2nd, 4) == asset_name})

      when reference_nft.3rd is {
        //Burn scenario (unlock of locked tokens)
        -1 -> {
          //Full asset unit
          let burned_unit = bytearray.concat(stake_key.1st, stake_key.2nd)
          //The time lock input
          expect Some(time_lock_input) =
            ctx.transaction.inputs |> find(fn(i) {
              i.output.address.payment_credential == ScriptCredential(time_lock_hash) && quantity_of(i.output.value, reference_nft.1st, reference_nft.2nd) == 1
            })

          //The inline datum belonging to the time lock inptu cast to TimeLockDatum
          expect InlineDatum(time_lock_input_datum) =
            time_lock_input.output.datum
          let time_lock_datum = to_time_lock_datum(time_lock_input_datum)

          //Ensure the tokens burned match the timelock key
          let correct_token_burned =
            time_lock_datum.extra.time_lock_key == burned_unit

          //Make sure both tokens are burned
          let both_burned = stake_key.3rd == reference_nft.3rd
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
      })
      and{
        correct_number_burned?,
        correct_burns?,
      }
    }
    _ -> False
  }
}

test lock_transaction_lock() {
  let current_time = 0

  let time_lock_hash =
    #"550cc5a9682bcbbe5583f1006624000032b4d8f4ddd6f37623462ff9"

  let stake_pool_hash =
    #"7a8a80f13e296da14c3c4e379e1c270ffabb2740a28e983acf75275f"

  let stake_proxy_hash =
    #"dc404ed342f5bc8344c8e2d21da7a45b8e0f70b5364ee4fda57dae75"

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

  let stake_key = concat(stake_key_prefix, asset_name)
  let reference_nft = concat(reference_prefix, asset_name)

  let meta_name =
    list.foldl(
      [
        "Stake Key ",
        abbreviated_amount(1_010_000, 0),
        " ",
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
             "https://my-stake-key-img.com/img.png",
             bytearray.compare,
           )
        |> dict.insert(
             "locked_amount",
             bytearray.from_string(string.from_int(1_010_000)),
             bytearray.compare,
           ),
      version: 1,
      extra: LockDatum {
        lock_until: current_time + hour_millis + 86_400_000,
        time_lock_key: #"00000000000000000000000000000000000000000000000000000011",
      },
    }

  expect Some(reward) = rational.new(1, 100)
  let stake_proxy_datum =
    StakeProxyDatum {
      owner: Signature(
        #"00000000000000000000000000000000000000000000000000000000",
      ),
      destination: Destination {
        address: Address {
          payment_credential: VerificationKeyCredential(
            #"00000000000000000000000000000000000000000000000000000000",
          ),
          stake_credential: None,
        },
        datum: NoDatum,
      },
      ms_locked: 86_400_000,
      reward_multiplier: reward,
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      key_policy_id: #"00000000000000000000000000000000000000000000000000000011",
      key_img_url: "https://my-stake-key-img.com/img.png",
    }

  let stake_proxy_output_reference =
    OutputReference { transaction_id: TransactionId(""), output_index: 1 }

  let stake_proxy_output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(stake_proxy_hash),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_000_000,
           ),
      datum: InlineDatum(stake_proxy_datum),
      reference_script: None,
    }
  let stake_proxy_input =
    Input {
      output_reference: stake_proxy_output_reference,
      output: stake_proxy_output,
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
  let stake_pool_datum =
    StakePoolDatum {
      owner: Signature(
        #"00000000000000000000000000000000000000000000000000000000",
      ),
      decimals: 0,
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      reward_settings: [
        RewardSetting { ms_locked: 86_400_000, reward_multiplier: reward },
      ],
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

  let stake_key_mint_redeemer =
    StakeKeyMintRedeemer {
      stake_pool_index: 0,
      time_lock_index: 0,
      stake_proxy_index: 1,
    }
  let context =
    ScriptContext {
      purpose: Mint(#"00000000000000000000000000000000000000000000000000000011"),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction {
               ..transaction,
               inputs: [stake_pool_input, stake_proxy_input],
               outputs: [time_lock_output],
               mint: zero()
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      stake_key,
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
  lock_transaction(
    stake_key_mint_redeemer,
    context,
    stake_pool_hash,
    stake_proxy_hash,
    time_lock_hash,
  ) && !unlock_transaction(context, time_lock_hash)
}

test unlock_transaction_single_unlock() {
  let current_time = 2 * 86_400_000

  let time_lock_hash =
    #"550cc5a9682bcbbe5583f1006624000032b4d8f4ddd6f37623462ff9"

  let stake_pool_hash =
    #"7a8a80f13e296da14c3c4e379e1c270ffabb2740a28e983acf75275f"

  let stake_proxy_hash =
    #"dc404ed342f5bc8344c8e2d21da7a45b8e0f70b5364ee4fda57dae75"

  let stake_key_mint_redeemer =
    StakeKeyMintRedeemer {
      stake_pool_index: 0,
      time_lock_index: 0,
      stake_proxy_index: 1,
    }

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

  let stake_key = concat(stake_key_prefix, asset_name)
  let reference_nft = concat(reference_prefix, asset_name)

  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum {
        lock_until: hour_millis + 86_400_000,
        time_lock_key: concat(#"00000000000000000000000000000000000000000000000000000011",stake_key),
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
                      stake_key,
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
                   bound_type: Finite(current_time+3_600_000),
                   is_inclusive: True,
                 },
               },
             }
           },
    }

    !lock_transaction(
    stake_key_mint_redeemer,
    context,
    stake_pool_hash,
    stake_proxy_hash,
    time_lock_hash,
  ) && unlock_transaction(context, time_lock_hash)
}

test unlock_transaction_multi_unlock() {
  let current_time = 2 * 86_400_000

  let time_lock_hash =
    #"550cc5a9682bcbbe5583f1006624000032b4d8f4ddd6f37623462ff9"

  let stake_pool_hash =
    #"7a8a80f13e296da14c3c4e379e1c270ffabb2740a28e983acf75275f"

  let stake_proxy_hash =
    #"dc404ed342f5bc8344c8e2d21da7a45b8e0f70b5364ee4fda57dae75"

  let stake_key_mint_redeemer =
    StakeKeyMintRedeemer {
      stake_pool_index: 0,
      time_lock_index: 0,
      stake_proxy_index: 1,
    }

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

  let stake_key_1 = concat(stake_key_prefix, asset_name_1)
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

  let stake_key_2 = concat(stake_key_prefix, asset_name_2)
  let reference_nft_2 = concat(reference_prefix, asset_name_2)

  let time_lock_datum_1 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum {
        lock_until: hour_millis + 86_400_000,
        time_lock_key: concat(#"00000000000000000000000000000000000000000000000000000011",stake_key_1),
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
        time_lock_key: concat(#"00000000000000000000000000000000000000000000000000000011",stake_key_2),
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
               inputs: [time_lock_input_1,time_lock_input_2],
               outputs: [],
               mint: zero()
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      stake_key_1,
                      -1,
                    )
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      reference_nft_1,
                      -1,
                    )
                 |> add(
                      #"00000000000000000000000000000000000000000000000000000011",
                      stake_key_2,
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
                   bound_type: Finite(current_time+3_600_000),
                   is_inclusive: True,
                 },
               },
             }
           },
    }

    !lock_transaction(
    stake_key_mint_redeemer,
    context,
    stake_pool_hash,
    stake_proxy_hash,
    time_lock_hash,
  ) && unlock_transaction(context, time_lock_hash)
}