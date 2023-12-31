use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list.{at}
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext, Spend, Transaction,
  TransactionId,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{add, from_lovelace}
use staking_contracts/datums.{
  LockDatum, RewardSetting, StakePoolDatum, StakePoolRedeemer, StakeProxyDatum,
  TimeLockDatum,
}
use staking_contracts/utils.{
  add_percentage, day_millis, hour_millis, must_be_locked_until,
  must_be_signed_by, must_have_exactly_one_output, stake_pool_hash,
  stake_proxy_hash, time_lock_hash,
}

validator {
  fn stake_pool(
    datum: StakePoolDatum,
    redeemer: StakePoolRedeemer,
    ctx: ScriptContext,
  ) {
    when ctx.purpose is {
      //Ensure the utxo is spent by either the owner or a valid locking tx
      Spend(my_output_reference) -> or {
          must_be_signed_by(ctx.transaction, datum.owner)?,
          is_proper_locking_tx(my_output_reference, datum, redeemer, ctx)?,
        }
      _ -> False
    }
  }
}

fn is_proper_locking_tx(
  my_output_reference: OutputReference,
  datum: StakePoolDatum,
  redeemer: StakePoolRedeemer,
  ctx: ScriptContext,
) {
  //Find the input guarded by this validator
  expect Some(self) =
    ctx.transaction.inputs
      |> transaction.find_input(my_output_reference)

  //We need to ensure the output of the tx has the same validator attached
  expect ScriptCredential(self_script) = self.output.address.payment_credential
  let self_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(self_script)
  expect Some(self_output) = self_outputs |> at(0)

  //The output needs to include a utxo with time lock validator
  let time_lock_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(time_lock_hash)
  expect Some(time_lock) = time_lock_outputs |> at(0)

  //We use the reward setting as indicated by the submitter of the transaction
  expect Some(reward_setting) =
    datum.reward_settings |> at(redeemer.reward_index)
  //Find out current stake_pool token quantity
  let stake_pool_size =
    self.output.value
      |> value.quantity_of(datum.policy_id, datum.asset_name)

  //Find stake_pool token quantity in output
  let new_stake_pool_size =
    self_output.value
      |> value.quantity_of(datum.policy_id, datum.asset_name)

  //Difference between old and new quantity is equal to the reward to the staker
  let reward = stake_pool_size - new_stake_pool_size

  //The locked amount in the time lock output
  let locked_amount =
    time_lock.value
      |> value.quantity_of(datum.policy_id, datum.asset_name)

  //The staked amount is deduced from the locked amount and the reward
  let staked_amount = locked_amount - reward

  //Ensure the locked amount matches the reward setting
  let correct_locked_amount =
    locked_amount == add_percentage(
      staked_amount,
      reward_setting.percentage_reward,
    )

  //Make sure no other assets have been altered in the stake pool output compared to the input
  let correct_output_value =
    self.output.value == add(
      self_output.value,
      datum.policy_id,
      datum.asset_name,
      reward,
    )

  //Make sure settings have not been altered
  let same_datum = InlineDatum(datum) == self_output.datum

  and {
    //Ensure exactly one stake pool output
    must_have_exactly_one_output(self_outputs)?,
    //Ensure exactly one time lock output
    must_have_exactly_one_output(time_lock_outputs)?,
    same_datum?,
    correct_locked_amount?,
    //Ensure that the time lock does not expire too soon
    must_be_locked_until(
      ctx.transaction.validity_range,
      time_lock,
      reward_setting.days_locked,
      hour_millis,
    )?,
    correct_output_value?,
  }
}

test stake_pool_lock_funds() {
  let stake_pool_datum =
    StakePoolDatum {
      owner: #"00000000000000000000000000000000000000000000000000000000",
      decimals: 0,
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      reward_settings: [RewardSetting { days_locked: 1, percentage_reward: 1 }],
    }

  let stake_proxy_datum =
    StakeProxyDatum {
      owner: #"00000000000000000000000000000000000000000000000000000000",
      days_locked: 1,
      reward_percentage: 1,
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      key_policy_id: #"00000000000000000000000000000000000000000000000000000011",
      key_img_url: "https://my-stake-key-img.com/img.png",
    }

  let current_time = 0
  let later_time = 2 * hour_millis

  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum {
        lock_until: current_time + hour_millis + day_millis,
        time_lock_key: #"00000000000000000000000000000000000000000000000000000011",
      },
    }
  let time_lock_data: Data = time_lock_datum

  let redeemer = StakePoolRedeemer { reward_index: 0 }
  let stake_pool_output_reference =
    OutputReference { transaction_id: TransactionId(""), output_index: 0 }

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

  //datum: stake_pool_datum,
  //reference_script: None,
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
           ),
      datum: InlineDatum(time_lock_data),
      reference_script: None,
    }
  let context =
    ScriptContext {
      purpose: Spend(stake_pool_output_reference),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction {
               ..transaction,
               inputs: [stake_pool_input, stake_proxy_input],
               outputs: [new_stake_pool_output, time_lock_output],
               validity_range: Interval {
                 lower_bound: IntervalBound {
                   bound_type: Finite(current_time),
                   is_inclusive: True,
                 },
                 upper_bound: IntervalBound {
                   bound_type: Finite(later_time),
                   is_inclusive: True,
                 },
               },
             }
           },
    }
  stake_pool(stake_pool_datum, redeemer, context)
}
