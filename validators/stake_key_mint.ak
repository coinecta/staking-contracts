use aiken/bytearray.{concat, drop, from_string, take}
use aiken/cbor.{diagnostic, serialise}
use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list.{at, find}
use aiken/math
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
  RewardSetting, StakePoolDatum, reference_prefix, stake_key_prefix,
  to_stake_pool_datum, to_time_lock_datum,
}
use staking_contracts/utils.{
  abbreviated_amount, must_start_after, time_to_date_string,
}

type StakeKeyMintRedeemer {
  stake_pool_index: Int,
  time_lock_index: Int,
}

validator {
  fn stake_key_mint(
    _datum: Void,
    redeemer: StakeKeyMintRedeemer,
    ctx: ScriptContext,
  ) {
    when ctx.purpose is {
      Mint(_policy_id) -> {
        trace @"gmm"
        let minted = from_minted_value(ctx.transaction.mint) |> flatten()
        trace diagnostic(minted)
        expect Some(reference_nft) =
          minted |> find(fn(mt) { take(mt.2nd, 4) == reference_prefix })
        expect Some(stake_key) =
          minted |> find(fn(mt) { take(mt.2nd, 4) == stake_key_prefix })
        let asset_name = drop(reference_nft.2nd, 4)
        let correct_stake_key_name = drop(stake_key.2nd, 4) == asset_name
        when reference_nft.3rd is {
          1 -> {
            trace @"mint"
            //token minted
            expect Some(stake_pool_input) =
              ctx.transaction.inputs |> at(redeemer.stake_pool_index)
            expect Some(time_lock_output) =
              ctx.transaction.outputs |> at(redeemer.time_lock_index)
            expect InlineDatum(stake_pool_input_datum) =
              stake_pool_input.output.datum
            let stake_pool_datum = to_stake_pool_datum(stake_pool_input_datum)

            expect InlineDatum(time_lock_output_datum) = time_lock_output.datum
            let time_lock_datum = to_time_lock_datum(time_lock_output_datum)
            expect Finite(tx_latest_time) =
              ctx.transaction.validity_range.upper_bound.bound_type
            let time_bytes = serialise(tx_latest_time)
            let output_ref_index_bytes =
              bytearray.from_string(
                string.from_int(stake_pool_input.output_reference.output_index),
              )
            let TransactionId(stake_pool_input_transaction_id) =
              stake_pool_input.output_reference.transaction_id

            let raw_amount =
              time_lock_output.value
                |> quantity_of(
                     stake_pool_datum.policy_id,
                     stake_pool_datum.asset_name,
                   )

            let amount = raw_amount / math.pow(10, stake_pool_datum.decimals)
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
            let correct_reference_name = asset_name == proper_asset_name
            let no_extra_mint = list.length(minted) == 2
            let correct_meta_name =
              dict.get(time_lock_datum.metadata, "name") == Some(
                proper_meta_name,
              )
            let correct_image =
              dict.get(time_lock_datum.metadata, "image") == Some(
                "https://my-stake-key-img.com/img.png",
              )
            //to do: add decimals
            let correct_meta_amount =
              dict.get(time_lock_datum.metadata, "locked_amount") == Some(
                bytearray.from_string(string.from_int(amount)),
              )
            and {
              correct_stake_key_name?,
              correct_reference_name?,
              no_extra_mint?,
              correct_meta_name?,
              correct_image?,
              correct_meta_amount?,
            }
          }
          -1 -> {
            let burned_unit = bytearray.concat(stake_key.1st, stake_key.2nd)
            //token burned
            expect Some(time_lock_input) =
              ctx.transaction.inputs |> at(redeemer.stake_pool_index)
            expect InlineDatum(time_lock_input_datum) =
              time_lock_input.output.datum
            let time_lock_datum = to_time_lock_datum(time_lock_input_datum)
            let correct_token_burned =
              time_lock_datum.extra.time_lock_key == burned_unit
            let no_extra_burn = list.length(minted) == 2
            let both_burned = stake_key.3rd == reference_nft.3rd
            and {
              must_start_after(
                ctx.transaction.validity_range,
                time_lock_datum.extra.lock_until,
              )?,
              correct_token_burned?,
              no_extra_burn?,
              both_burned?,
              correct_stake_key_name?,
            }
          }
          _ -> False
        }
      }
      _ -> False
    }
  }
}

test stake_key_mint_mint() {
  let stake_pool_datum =
    StakePoolDatum {
      owner: #"00000000000000000000000000000000000000000000000000000000",
      decimals: 0,
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      reward_settings: [RewardSetting { days_locked: 1, percentage_reward: 1 }],
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
        payment_credential: ScriptCredential(
          #"00000000000000000000000000000000000000000000000000000010",
        ),
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

  let stake_key_mint_redeemer =
    StakeKeyMintRedeemer { stake_pool_index: 0, time_lock_index: 0 }
  let context =
    ScriptContext {
      purpose: Mint(#"00000000000000000000000000000000000000000000000000000011"),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction {
               ..transaction,
               inputs: [stake_pool_input],
               outputs: [],
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
  stake_key_mint(Void, stake_key_mint_redeemer, context)
}
