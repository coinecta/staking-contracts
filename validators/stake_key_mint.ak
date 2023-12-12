use aiken/bytearray.{concat, from_string}
use aiken/cbor.{diagnostic}
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list.{at}
use aiken/string.{from_int}
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, ScriptContext, Spend,
  Transaction, TransactionId,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{
  add, flatten, from_lovelace, from_minted_value, to_minted_value, zero,
}
use staking_contracts/datums.{
  RewardSetting, StakePoolDatum, to_stake_pool_datum, to_time_lock_datum,
}
use staking_contracts/utils.{must_start_after}

type StakeKeyMintRedeemer {
  stake_pool_index: Int,
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
        expect Some(minted_token) = minted |> at(0)
        when minted_token.3rd is {
          1 -> {
            trace @"mint"
            //token minted
            expect Some(stake_pool_input) =
              ctx.transaction.inputs |> at(redeemer.stake_pool_index)
            trace diagnostic(stake_pool_input)
            expect InlineDatum(stake_pool_input_datum) =
              stake_pool_input.output.datum
            trace diagnostic(stake_pool_input_datum)
            let stake_pool_datum = to_stake_pool_datum(stake_pool_input_datum)
            expect Finite(tx_latest_time) =
              ctx.transaction.validity_range.upper_bound.bound_type
            //Ms second precision not needed, time bytearray length 8 
            let time_bytes =
              bytearray.from_string(string.from_int(tx_latest_time / 100000))
            let output_ref_index_bytes =
              bytearray.from_string(
                string.from_int(stake_pool_input.output_reference.output_index),
              )
            // Asset name for stake key:
            // s-{staked_asset}-{stake_time}{stake_pool_input tx id & index}
            let TransactionId(stake_pool_input_transaction_id) =
              stake_pool_input.output_reference.transaction_id
            let proper_asset_name =
              bytearray.concat(
                #"732d",
                bytearray.concat(
                  bytearray.take(stake_pool_datum.asset_name, 8),
                  bytearray.concat(
                    #"2d",
                    bytearray.concat(
                      time_bytes,
                      bytearray.concat(
                        output_ref_index_bytes,
                        bytearray.from_string(
                          bytearray.to_hex(
                            bytearray.take(stake_pool_input_transaction_id, 6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            trace diagnostic(minted_token.2nd)
            trace diagnostic(proper_asset_name)
            let correct_mint = minted_token.2nd == proper_asset_name
            correct_mint?
          }
          -1 -> {
            let burned_unit =
              bytearray.concat(minted_token.1st, minted_token.2nd)
            //token burned
            expect Some(time_lock_input) =
              ctx.transaction.inputs |> at(redeemer.stake_pool_index)
            expect InlineDatum(time_lock_input_datum) =
              time_lock_input.output.datum
            let time_lock_datum = to_time_lock_datum(time_lock_input_datum)
            let correct_token_burned =
              time_lock_datum.time_lock_key == burned_unit
            and {
              must_start_after(
                ctx.transaction.validity_range,
                time_lock_datum.lock_until,
              )?,
              correct_token_burned?,
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
      time_lock_hash: #"00000000000000000000000000000000000000000000000000000000",
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

  let stake_key =
    concat(
      from_string(@"s-"),
      concat(
        #"000000000000",
        concat(
          from_string(@"-"),
          concat(
            from_string(from_int(3_600_000 / 100000)),
            concat(from_string(@"0"), from_string(@"0000000000")),
          ),
        ),
      ),
    )

  let stake_key_mint_redeemer = StakeKeyMintRedeemer { stake_pool_index: 0 }
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
