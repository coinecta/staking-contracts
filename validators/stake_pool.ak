use aiken/list.{at}
use aiken/transaction.{OutputReference, ScriptContext, Spend}
use aiken/transaction/value.{add}
use staking_contracts/datums.{
  StakePoolDatum, StakePoolRedeemer, to_stake_pool_datum,
}
use staking_contracts/utils.{
  add_percentage, must_be_locked_until, must_be_signed_by,
  must_have_exactly_one_output, must_have_same_datum,
}

validator {
  fn stake_pool(
    datum: StakePoolDatum,
    redeemer: StakePoolRedeemer,
    ctx: ScriptContext,
  ) {
    when ctx.purpose is {
      Spend(my_output_reference) -> or {
          must_be_signed_by(ctx.transaction, datum.owner),
          is_proper_locking_tx(my_output_reference, datum, redeemer, ctx),
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
  expect Some(self) =
    ctx.transaction.inputs
      |> transaction.find_input(my_output_reference)
  expect Some(self_script) = self.output.reference_script
  let self_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(self_script)
  expect Some(self_output) = self_outputs |> at(0)
  let time_lock_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(datum.time_lock_contract_hash)
  expect Some(time_lock) = time_lock_outputs |> at(0)
  expect Some(reward_setting) =
    datum.reward_settings |> at(redeemer.reward_index)
  let stake_pool_size =
    self.output.value
      |> value.quantity_of(datum.policy_id, datum.asset_name)
  let new_stake_pool_size =
    self_output.value
      |> value.quantity_of(datum.policy_id, datum.asset_name)
  let reward = stake_pool_size - new_stake_pool_size
  let locked_amount =
    time_lock.value
      |> value.quantity_of(datum.policy_id, datum.asset_name)
  let staked_amount = locked_amount - reward
  and {
    must_have_exactly_one_output(self_outputs),
    must_have_exactly_one_output(time_lock_outputs),
    must_have_same_datum(datum, to_stake_pool_datum(self_output.datum)),
    time_lock.reference_script == Some(datum.time_lock_contract_hash),
    locked_amount == add_percentage(
      staked_amount,
      reward_setting.percentage_reward,
    ),
    must_be_locked_until(
      ctx.transaction.validity_range,
      time_lock,
      reward_setting.days_locked,
    ),
    self.output.value == add(
      self_output.value,
      datum.policy_id,
      datum.asset_name,
      reward,
    ),
  }
}
