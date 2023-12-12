use aiken/interval.{Finite}
use aiken/list.{has, length}
use aiken/time.{PosixTime}
use aiken/transaction.{InlineDatum, Output, Transaction, ValidityRange}
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

pub const hour_millis = 3_600_000

//Ensure that the time_lock output is set to expire after a set amount of days, with a certain buffer
//to allow for a realistic transaction validity range
pub fn must_be_locked_until(
  range: ValidityRange,
  time_lock: Output,
  days_to_be_locked: Int,
  buffer: Int,
) {
  expect InlineDatum(time_lock_datum) = time_lock.datum
  let lock_expiration_time = to_time_lock_datum(time_lock_datum).lock_until
  and {
    //This ensures for the user that the assets are not locked longer than expected
    when range.lower_bound.bound_type is {
      Finite(tx_earliest_time) ->
        tx_earliest_time + days_to_be_locked * day_millis + buffer >= lock_expiration_time
      _ -> False
    },
    //This ensures assets are locked for at least the required amount as configured in the stake pool
    when range.upper_bound.bound_type is {
      Finite(tx_latest_time) ->
        tx_latest_time + days_to_be_locked * day_millis - buffer <= lock_expiration_time
      _ -> False
    },
  }
}

pub fn must_start_after(range: ValidityRange, lock_expiration_time: PosixTime) {
  when range.lower_bound.bound_type is {
    Finite(tx_earliest_time) -> lock_expiration_time <= tx_earliest_time
    _ -> False
  }
}

test must_have_same_datum_succeed_when_same_datum() {
  let time_lock_datum_1 = TimeLockDatum { lock_until: 0, time_lock_key: #"" }
  let time_lock_datum_2 = TimeLockDatum { lock_until: 0, time_lock_key: #"" }
  must_have_same_datum(time_lock_datum_1, time_lock_datum_2)
}

test must_have_same_datum_fail_when_different_datum() {
  let time_lock_datum_1 = TimeLockDatum { lock_until: 0, time_lock_key: #"" }
  let time_lock_datum_2 = TimeLockDatum { lock_until: 1, time_lock_key: #"" }
  !must_have_same_datum(time_lock_datum_1, time_lock_datum_2)
}

test must_have_same_datum_fail_when_different_datum_type() {
  let time_lock_datum = TimeLockDatum { lock_until: 0, time_lock_key: #"" }
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

test must_start_after_succeed_when_lower_bound_is_after() {
  must_start_after(interval.after(2), 1)
}

test must_start_after_succeed_when_lower_bound_is_equal() {
  must_start_after(interval.after(2), 2)
}

test must_start_after_fail_when_lower_bound_is_before() {
  !must_start_after(interval.after(2), 3)
}
