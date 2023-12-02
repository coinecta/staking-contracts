use aiken/interval.{Finite}
use aiken/list.{length}
use aiken/transaction.{Output, ScriptContext, Spend, ValidityRange}
use aiken/transaction/value
use staking_contracts/datums.{
  POSIXTime, StakePoolDatum, StakePoolRedeemer, TimeLockDatum,
}

validator {
  fn stake_pool(
    datum: StakePoolDatum,
    redeemer: StakePoolRedeemer,
    ctx: ScriptContext,
  ) {
    when ctx.purpose is {
      Spend(my_output_reference) -> {
        expect Some(self) =
          ctx.transaction.inputs
            |> transaction.find_input(my_output_reference)
        expect Some(self_script) = self.output.reference_script
        let self_outputs =
          ctx.transaction.outputs
            |> transaction.find_script_outputs(self_script)
        expect Some(self_output) = self_outputs |> list.at(0)
        let time_lock_outputs =
          ctx.transaction.outputs
            |> transaction.find_script_outputs(datum.time_lock_contract_hash)
        expect Some(time_lock) = time_lock_outputs |> list.at(0)
        expect Some(reward_setting) =
          datum.reward_settings |> list.at(redeemer.reward_index)
        let stake_pool_size =
          self.output.value
            |> value.quantity_of(datum.policy_id, datum.asset_name)
        let new_stake_pool_size =
          self_output.value
            |> value.quantity_of(datum.policy_id, datum.asset_name)
        let reward = stake_pool_size - new_stake_pool_size
        let staked_amount = reward / reward_setting.percentage_reward * 100
        let locked_amount =
          time_lock.value
            |> value.quantity_of(datum.policy_id, datum.asset_name)
        and {
          must_have_exactly_one_output(self_outputs),
          must_have_exactly_one_output(time_lock_outputs),
          must_have_same_datum(datum, to_stake_pool_datum(self_output.datum)),
          time_lock.reference_script == Some(datum.time_lock_contract_hash),
          locked_amount == staked_amount + reward,
          must_be_locked_until(
            ctx.transaction.validity_range,
            to_time_lock_datum(time_lock.datum).lock_until,
            reward_setting.days_locked,
          ),
        }
      }
      _ -> False
    }
  }
}

fn must_be_locked_until(
  range: ValidityRange,
  lock_expiration_time: POSIXTime,
  days_to_be_locked: Int,
) {
  when range.lower_bound.bound_type is {
    Finite(tx_earliest_time) ->
      tx_earliest_time + days_to_be_locked * 86400000 <= lock_expiration_time
    _ -> False
  }
}

fn must_have_exactly_one_output(outputs: List<Output>) {
  length(outputs) == 1
}

fn must_have_same_datum(
  input_datum: StakePoolDatum,
  output_datum: StakePoolDatum,
) {
  input_datum == output_datum
}

fn to_stake_pool_datum(data: Data) -> StakePoolDatum {
  expect my_datum: StakePoolDatum = data
  my_datum
}

fn to_time_lock_datum(data: Data) -> TimeLockDatum {
  expect my_datum: TimeLockDatum = data
  my_datum
}
