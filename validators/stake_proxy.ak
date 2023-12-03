use aiken/list
use aiken/transaction.{OutputReference, ScriptContext, Spend}
use aiken/transaction/value.{quantity_of}
use staking_contracts/datums.{StakeProxyDatum, to_time_lock_datum}
use staking_contracts/utils.{
  add_percentage, must_be_locked_until, must_be_signed_by,
  must_have_exactly_one_output,
}

validator {
  fn stake_proxy(datum: StakeProxyDatum, _redeemer: Void, ctx: ScriptContext) {
    when ctx.purpose is {
      Spend(my_output_reference) -> or {
          must_be_signed_by(ctx.transaction, datum.owner),
          is_proper_locking_tx(my_output_reference, datum, ctx),
        }
      _ -> False
    }
  }
}

fn is_proper_locking_tx(
  my_output_reference: OutputReference,
  datum: StakeProxyDatum,
  ctx: ScriptContext,
) {
  expect Some(self) =
    ctx.transaction.inputs
      |> transaction.find_input(my_output_reference)
  let time_lock_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(datum.time_lock_contract_hash)
  expect Some(time_lock_output) = time_lock_outputs |> list.at(0)
  let time_lock_datum = to_time_lock_datum(time_lock_output.datum)
  let staked_tokens =
    self.output.value
      |> quantity_of(datum.policy_id, datum.asset_name)
  let locked_tokens =
    time_lock_output.value
      |> quantity_of(datum.policy_id, datum.asset_name)
  and {
    must_have_exactly_one_output(time_lock_outputs),
    time_lock_datum.owner == datum.owner,
    must_be_locked_until(
      ctx.transaction.validity_range,
      time_lock_output,
      datum.days_locked,
    ),
    locked_tokens == add_percentage(staked_tokens, datum.reward_percentage),
  }
}
