use aiken/interval.{Finite}
use aiken/list.{has, length}
use aiken/transaction.{Output, Transaction, ValidityRange}
use staking_contracts/datums.{
  StakePoolDatum, TimeLockDatum, VerificationKeyHash, to_time_lock_datum,
}

pub fn must_have_exactly_one_output(outputs: List<Output>) {
  length(outputs) == 1
}

pub fn must_have_same_datum(input_datum: Data, output_datum: Data) {
  input_datum == output_datum
}

pub fn must_be_signed_by(transaction: Transaction, vk: VerificationKeyHash) {
  has(transaction.extra_signatories, vk)
}

pub fn add_percentage(amount: Int, percentage: Int) -> Int {
  amount * ( 100 + percentage ) / 100
}

pub const day_millis = 86_400_000

pub fn must_be_locked_until(
  range: ValidityRange,
  time_lock: Output,
  days_to_be_locked: Int,
) {
  when range.lower_bound.bound_type is {
    Finite(tx_earliest_time) -> {
      let lock_expiration_time = to_time_lock_datum(time_lock.datum).lock_until
      and {
        tx_earliest_time + days_to_be_locked * day_millis <= lock_expiration_time,
        tx_earliest_time + days_to_be_locked * day_millis + 300000 >= lock_expiration_time,
      }
    }
    _ -> False
  }
}

test must_have_same_datum_succeed_when_same_datum() {
  let time_lock_datum_1 = TimeLockDatum { lock_until: 0, owner: #"" }
  let time_lock_datum_2 = TimeLockDatum { lock_until: 0, owner: #"" }
  must_have_same_datum(time_lock_datum_1, time_lock_datum_2)
}

test must_have_same_datum_fail_when_different_datum() {
  let time_lock_datum_1 = TimeLockDatum { lock_until: 0, owner: #"" }
  let time_lock_datum_2 = TimeLockDatum { lock_until: 1, owner: #"" }
  !must_have_same_datum(time_lock_datum_1, time_lock_datum_2)
}

test must_have_same_datum_fail_when_different_datum_type() {
  let time_lock_datum = TimeLockDatum { lock_until: 0, owner: #"" }
  let stake_pool_datum =
    StakePoolDatum {
      time_lock_hash: #"",
      reward_settings: [],
      policy_id: #"",
      asset_name: #"",
      owner: #"",
    }
  !must_have_same_datum(time_lock_datum, stake_pool_datum)
}

test add_percentage_succeed_normal_case() {
  add_percentage(1000, 1) == 1010
}

test add_percentage_succeed_floored_value() {
  add_percentage(90, 1) == 90
}
