use aiken/list
use aiken/interval.{Interval,IntervalBound, Finite}
use aiken/transaction.{OutputReference, ScriptContext, Spend, TransactionId, Transaction, Output, Input, InlineDatum}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{quantity_of, add, from_lovelace}
use staking_contracts/datums.{StakeProxyDatum, to_time_lock_datum, StakePoolDatum, RewardSetting, TimeLockDatum}
use staking_contracts/utils.{
  add_percentage, must_be_locked_until, must_be_signed_by,
  must_have_exactly_one_output, hour_millis
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

  //Ensure that the owner of the proxy is also the owner of the time lock
  let correct_owner = time_lock_datum.owner == datum.owner

  //Ensure locked tokens is staked + reward
  let correct_locked_tokens = locked_tokens == add_percentage(staked_tokens, datum.reward_percentage)

  and {
    //Ensure only one time lock output to avoid unexpected results
    must_have_exactly_one_output(time_lock_outputs)?,
    correct_owner?,
    //Make sure the time lock does not lock the assets too long
    must_be_locked_until(
      ctx.transaction.validity_range,
      time_lock_output,
      datum.days_locked,
      hour_millis
    )?,
    correct_locked_tokens?,
  }
}

test stake_proxy_lock_funds() {
  let stake_pool_datum = StakePoolDatum {
    owner: #"00000000000000000000000000000000000000000000000000000000",
    time_lock_hash: #"00000000000000000000000000000000000000000000000000000000",
    policy_id: #"00000000000000000000000000000000000000000000000000000000",
    asset_name: #"000000000000",
    reward_settings: [RewardSetting {days_locked: 1, percentage_reward: 1}]
  }

  let stake_proxy_datum = StakeProxyDatum {
    owner: #"00000000000000000000000000000000000000000000000000000000",
  days_locked: 1,
  reward_percentage: 1,
  time_lock_hash: #"00000000000000000000000000000000000000000000000000000000",
  policy_id: #"00000000000000000000000000000000000000000000000000000000",
  asset_name: #"000000000000",
  }

  let time_lock_datum = TimeLockDatum {
    lock_until: 86400000,
    /// Owner's credentials
    owner: #"00000000000000000000000000000000000000000000000000000000",
  }
  let time_lock_data: Data = time_lock_datum

  let redeemer =
    Void
 
  let stake_pool_output_reference =
    OutputReference { transaction_id: TransactionId(""), output_index: 0 }

  let stake_pool_output = Output {
    address: Address { payment_credential: ScriptCredential(#"00000000000000000000000000000000000000000000000000000010"), stake_credential: None },
    value: from_lovelace(2000000) |> add(#"00000000000000000000000000000000000000000000000000000000",#"000000000000", 1_000_000_000),
    datum: InlineDatum(stake_pool_datum),
    reference_script: None,
  }

  let stake_pool_input = Input {
    output_reference: stake_pool_output_reference, output: stake_pool_output
  }

  let stake_proxy_output_reference =
    OutputReference { transaction_id: TransactionId(""), output_index: 1 }

  let stake_proxy_output = Output {
    address: Address { payment_credential: ScriptCredential(#"00000000000000000000000000000000000000000000000000000020"), stake_credential: None },
    value: from_lovelace(2000000) |> add(#"00000000000000000000000000000000000000000000000000000000",#"000000000000", 1_000_000),
    datum: InlineDatum(stake_proxy_datum),
    reference_script: None,
  }
  
  let stake_proxy_input = Input {
    output_reference: stake_proxy_output_reference, output: stake_proxy_output
  }

  let new_stake_pool_output = Output { ..stake_pool_output ,
    //address: Address { payment_credential: #"00000000000000000000000000000000000000000000000000000010", stake_credential: None },
    value: from_lovelace(2000000) |> add(#"00000000000000000000000000000000000000000000000000000000",#"000000000000", 999_990_000),
    //datum: stake_pool_datum,
    //reference_script: None,
  }

  let time_lock_output = Output {
    address: Address { payment_credential: ScriptCredential(#"00000000000000000000000000000000000000000000000000000000"), stake_credential: None },
    value: from_lovelace(2000000) |> add(#"00000000000000000000000000000000000000000000000000000000",#"000000000000", 1_010_000),
    datum: InlineDatum(time_lock_data),
    reference_script: None,
  }
  
 
  let context =
    ScriptContext {
      purpose: Spend(stake_proxy_output_reference),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction { ..transaction, inputs: [stake_pool_input, stake_proxy_input], outputs: [new_stake_pool_output, time_lock_output], validity_range: Interval {
  lower_bound: IntervalBound { bound_type: Finite(0), is_inclusive: True },
  upper_bound: IntervalBound { bound_type: Finite(3_600_000), is_inclusive: True },
} }
           }
    }
 
  stake_proxy(stake_proxy_datum, redeemer, context)
}
