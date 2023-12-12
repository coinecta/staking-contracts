use aiken/bytearray
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list.{find}
use aiken/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext, Spend,
  Transaction, TransactionId,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential, from_verification_key,
}
use aiken/transaction/value.{
  add, from_lovelace, from_minted_value, quantity_of, to_minted_value, zero,
}
use staking_contracts/datums.{
  RewardSetting, StakePoolDatum, StakeProxyDatum, TimeLockDatum,
  to_time_lock_datum,
}
use staking_contracts/utils.{
  add_percentage, hour_millis, must_be_locked_until, must_be_signed_by,
  must_have_exactly_one_output,
}

validator {
  fn stake_proxy(datum: StakeProxyDatum, _redeemer: Void, ctx: ScriptContext) {
    when ctx.purpose is {
      //The proxy needs to be spend in a locking transaction or in a manual refund
      Spend(my_output_reference) -> or {
          must_be_signed_by(ctx.transaction, datum.owner)?,
          is_proper_locking_tx(my_output_reference, datum, ctx)?,
        }
      _ -> False
    }
  }
}

//Ensures that tokens are locked for the duration the user requests
//and that the reward is matching the expectation
fn is_proper_locking_tx(
  my_output_reference: OutputReference,
  datum: StakeProxyDatum,
  ctx: ScriptContext,
) {
  //Find the input this validator is attached to
  expect Some(self) =
    ctx.transaction.inputs
      |> transaction.find_input(my_output_reference)
  //Find the output locking the staked tokens + reward and extract its datum
  let time_lock_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(datum.time_lock_hash)
  expect Some(time_lock_output) = time_lock_outputs |> list.at(0)
  expect InlineDatum(time_lock_output_datum) = time_lock_output.datum
  let time_lock_datum = to_time_lock_datum(time_lock_output_datum)

  //We assume all assets matching the policy_id+asset_name are to be staked
  let staked_tokens =
    self.output.value
      |> quantity_of(datum.policy_id, datum.asset_name)

  //The amount of tokens locked, should be staked + reward
  let locked_tokens =
    time_lock_output.value
      |> quantity_of(datum.policy_id, datum.asset_name)

  //Find minted stake key
  let minted = from_minted_value(ctx.transaction.mint)

  let minted_policy_id = bytearray.take(time_lock_datum.time_lock_key, 28)

  let minted_asset_name = bytearray.drop(time_lock_datum.time_lock_key, 28)

  //Make sure the minted key is using the expected policy_id
  let correct_stake_key_policy_id = minted_policy_id == datum.key_policy_id

  //Make sure only 1 is minted
  let correct_key_minted =
    quantity_of(minted, minted_policy_id, minted_asset_name) == 1

  //Make sure the key is minted into the users' wallet
  expect Some(_key_minted_to_user) =
    ctx.transaction.outputs
      |> find(
           fn(o) {
             quantity_of(o.value, minted_policy_id, minted_asset_name) == 1 && o.address.payment_credential == VerificationKeyCredential(
               datum.owner,
             )
           },
         )

  //Ensure locked tokens is staked + reward
  let correct_locked_tokens =
    locked_tokens == add_percentage(staked_tokens, datum.reward_percentage)

  and {
    //Ensure only one time lock output to avoid unexpected results
    must_have_exactly_one_output(time_lock_outputs)?,
    correct_stake_key_policy_id?,
    //Make sure the time lock does not lock the assets too long
    must_be_locked_until(
      ctx.transaction.validity_range,
      time_lock_output,
      datum.days_locked,
      hour_millis,
    )?,
    correct_locked_tokens?,
    correct_key_minted?,
  }
}

test stake_proxy_lock_funds() {
  let stake_pool_datum =
    StakePoolDatum {
      owner: #"00000000000000000000000000000000000000000000000000000000",
      time_lock_hash: #"00000000000000000000000000000000000000000000000000000000",
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      reward_settings: [RewardSetting { days_locked: 1, percentage_reward: 1 }],
    }

  let stake_proxy_datum =
    StakeProxyDatum {
      owner: #"00000000000000000000000000000000000000000000000000000000",
      days_locked: 1,
      reward_percentage: 1,
      time_lock_hash: #"00000000000000000000000000000000000000000000000000000000",
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      key_policy_id: #"00000000000000000000000000000000000000000000000000000011",
    }

  let time_lock_datum =
    TimeLockDatum {
      lock_until: 86400000,
      time_lock_key: #"00000000000000000000000000000000000000000000000000000011",
    }
  let time_lock_data: Data = time_lock_datum

  let redeemer = Void
  let stake_pool_output_reference =
    OutputReference { transaction_id: TransactionId(""), output_index: 0 }

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

  let stake_proxy_output_reference =
    OutputReference { transaction_id: TransactionId(""), output_index: 1 }

  let stake_proxy_output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(
          #"00000000000000000000000000000000000000000000000000000020",
        ),
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

  let new_stake_pool_output =
    Output {
      ..stake_pool_output,
      value: //address: Address { payment_credential: #"00000000000000000000000000000000000000000000000000000010", stake_credential: None },
      from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             999_990_000,
           ),
    }

  let user_output =
    Output {
      address: from_verification_key(stake_proxy_datum.owner),
      value: from_lovelace(100000)
        |> add(stake_proxy_datum.key_policy_id, #"", 1),
      reference_script: None,
      datum: NoDatum,
    }

  //datum: stake_pool_datum,
  //reference_script: None,
  let time_lock_output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(
          #"00000000000000000000000000000000000000000000000000000000",
        ),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_010_000,
           ),
      datum: InlineDatum(time_lock_data),
      reference_script: None,
    }
  let context =
    ScriptContext {
      purpose: Spend(stake_proxy_output_reference),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction {
               ..transaction,
               inputs: [stake_pool_input, stake_proxy_input],
               outputs: [new_stake_pool_output, time_lock_output, user_output],
               mint: zero()
                 |> add(stake_proxy_datum.key_policy_id, #"", 1)
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
  stake_proxy(stake_proxy_datum, redeemer, context)
}
/// Owner's credentials
