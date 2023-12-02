use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{ScriptContext, Spend, Transaction, ValidityRange}
use staking_contracts/datums.{POSIXTime, TimeLockDatum, VerificationKeyHash}

validator {
  fn time_lock(datum: TimeLockDatum, _redeemer: Void, ctx: ScriptContext) {
    when ctx.purpose is {
      Spend(_) -> and {
          must_be_signed_by(ctx.transaction, datum.owner),
          must_start_after(ctx.transaction.validity_range, datum.lock_until),
        }
      _ -> False
    }
  }
}

fn must_be_signed_by(transaction: Transaction, vk: VerificationKeyHash) {
  list.has(transaction.extra_signatories, vk)
}

fn must_start_after(range: ValidityRange, lock_expiration_time: POSIXTime) {
  when range.lower_bound.bound_type is {
    Finite(tx_earliest_time) -> lock_expiration_time <= tx_earliest_time
    _ -> False
  }
}

test must_start_after_succeed_when_lower_bound_is_after() {
  must_start_after(interval.after(2), 1)
}

test must_start_after_succeed_when_lower_bound_is_equal() {
  must_start_after(interval.after(2), 2)
}

test must_start_after_fail_when_lower_bound_is_before() {
  !must_start_after(interval.after(2), 3)
}
