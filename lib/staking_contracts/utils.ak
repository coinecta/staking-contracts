use aiken/bytearray.{drop, take}
use aiken/dict
use aiken/interval.{Finite}
use aiken/list.{filter, find, has, length}
use aiken/math/rational.{Rational}
use aiken/option.{is_some}
use aiken/string
use aiken/time.{PosixTime}
use aiken/transaction.{InlineDatum, Input, Output, Transaction, ValidityRange}
use aiken/transaction/credential.{Credential}
use aiken/transaction/value.{quantity_of}
use staking_contracts/datums.{
  LockDatum, StakePoolDatum, TimeLockDatum, VerificationKeyHash,
  to_time_lock_datum,
}
use sundae/multisig.{Signature}

// Spec 1.5.3, 4.3.3
pub fn filter_inputs_by_credential(inputs: List<Input>, cred: Credential) {
  inputs |> filter(fn(i) { i.output.address.payment_credential == cred })
}

// Spec 1.5.3 + 1.5.6 - uniqueness of outputs
pub fn must_have_exactly_one_output(outputs: List<Output>) {
  length(outputs) == 1
}

// UNUSED
pub fn must_have_same_datum(input_datum: Data, output_datum: Data) {
  input_datum == output_datum
}

// UNUSED
pub fn must_be_signed_by(transaction: Transaction, vk: VerificationKeyHash) {
  has(transaction.extra_signatories, vk)
}

// Spec 1.5.13.4, 4.3.2.20
pub fn add_reward(amount: Int, reward: Rational) -> Int {
  // Spec 1.5.10, 4.3.2.19
  expect Less != rational.compare(reward, rational.zero())
  // Spec 1.5.13.4, 4.3.2.20 - "rounded down"
  rational.floor(
    // Spec 1.5.13.4, 4.3.2.20 - "multiplied by"
    rational.mul(
      // Spec 1.5.13.4, 4.3.2.20 - "derived_user_locked_output" => amount, which comes from staked_amount
      rational.from_int(amount),
      // Spec 1.5.13.4, 4.3.2.20 - "1 + reward_multiplier"
      rational.add(rational.from_int(1), reward),
    ),
  )
}

//Returns true if the list of outputs contains at least 1 of the provided unit
// Spec 4.3.2.2 - n.b. unit is equal to `batcher_certificate`
pub fn must_contain_asset(outputs: List<Output>, unit: ByteArray) -> Bool {
  // Spec 4.3.2.2 - "with a policy ID equal to the first 28 bytes of batcher certificate"
  let policy_id = unit |> take(28)
  // Spec 4.3.2.2 - "an asset name equal to the remainder of the batcher certificate"
  let asset_id = unit |> drop(28)
  // Spec 4.3.2.2 - "Must have at least one"
  is_some(
    // Spec 4.3.2.2 - "one output such that"
    outputs |> find(fn(o) {
      // Spec 4.3.2.2 - "the value on that output contains an asset" "and a quantity greater than 0"
      quantity_of(o.value, policy_id, asset_id) > 0 }),
  )
}

// Spec 1.5.11
pub const hour_millis = 3_600_000

//Ensure that the time_lock output is set to expire after a set amount of days, with a certain buffer
//to allow for a realistic transaction validity range
// Spec 1.5.11 + 1.5.12
pub fn must_be_locked_until(
  range: ValidityRange,
  time_lock: Output,
  ms_to_be_locked: Int,
  buffer: Int, // n.b. passed buffer
) {
  // Spec 1.5.12 - "the datum attached to the time lock position"
  expect InlineDatum(time_lock_datum) = time_lock.datum
  // Spec 1.5.12 - "has extra.lock_until"
  let lock_expiration_time =
    to_time_lock_datum(time_lock_datum).extra.lock_until
  // Spec 1.5.11 - "two finite bounds"
  expect Finite(upper_bound) = range.upper_bound.bound_type
  expect Finite(lower_bound) = range.lower_bound.bound_type

  // Spec 1.5.12 - "upper_bound + reward_setting.ms_locked"
  let correct_lock_time = upper_bound + ms_to_be_locked

  // Spec 1.5.12 - "is equal to"
  let is_locked_until_correct_time = lock_expiration_time == correct_lock_time
  // Spec 1.5.11 - "that differ by at most"
  let range_less_than_buffer = upper_bound - lower_bound <= buffer
  and {
    // Spec 1.5.12
    is_locked_until_correct_time?,
    // Spec 1.5.11
    range_less_than_buffer?,
  }
}

// Spec 2.6.8.8, 3.3.3
pub fn must_start_after(range: ValidityRange, lock_expiration_time: PosixTime) {
  // Spec 2.6.8.8 - "the transaction lower bound must be"
  when range.lower_bound.bound_type is {
    // Spec 2.6.8.8 - Finite, and after or equal to `extra.lock_until`
    // n.b. lock_expiration_time comes from extra.lock_until
    Finite(tx_earliest_time) -> lock_expiration_time <= tx_earliest_time
    _ -> False
  }?
}

//Produces a date string in the format YYYYMMDD
//Taken from https://stackoverflow.com/questions/7136385/calculate-day-number-from-an-unix-timestamp-in-a-math-way
// Spec 2.5.18 - n.b. because of the complexity, the details of this code are not covered by the audit
pub fn time_to_date_string(time: PosixTime) -> ByteArray {
  let s = time / 1000
  let z = s / 86400 + 719468
  let era =
    if z >= 0 {
      z
    } else {
      z - 146096
    } / 146097
  let doe = z - era * 146097
  let yoe = ( doe - doe / 1460 + doe / 36524 - doe / 146096 ) / 365
  let y = yoe + era * 400
  let doy = doe - ( 365 * yoe + yoe / 4 - yoe / 100 )
  let mp = ( 5 * doy + 2 ) / 153
  let d = doy - ( 153 * mp + 2 ) / 5 + 1
  let m =
    mp + if mp < 10 {
      3
    } else {
      -9
    }
  let adjusted_y =
    y + if m <= 2 {
      1
    } else {
      0
    }
  let year_string = string.from_int(adjusted_y)
  let month_string =
    string.concat(
      if m < 10 {
        @"0"
      } else {
        @""
      },
      string.from_int(m),
    )
  let day_string =
    string.concat(
      if d < 10 {
        @"0"
      } else {
        @""
      },
      string.from_int(d),
    )
  string.to_bytearray(string.join([year_string, month_string, day_string], @""))
    |> bytearray.drop(2)
}

test time_to_date_string_correct_regular_date() {
  time_to_date_string(1703851519000) == "231229"
}

test time_to_date_string_correct_leap_day_date() {
  time_to_date_string(1709208319000) == "240229"
}

test time_to_date_string_correct_day_less_than_10_date() {
  time_to_date_string(1706875519000) == "240202"
}

test must_have_same_datum_succeed_when_same_datum() {
  let time_lock_datum_1 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 0, time_lock_nft: #"" },
    }
  let time_lock_datum_2 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 0, time_lock_nft: #"" },
    }
  must_have_same_datum(time_lock_datum_1, time_lock_datum_2)
}

test must_have_same_datum_fail_when_different_datum() {
  let time_lock_datum_1 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 0, time_lock_nft: #"" },
    }
  let time_lock_datum_2 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 1, time_lock_nft: #"" },
    }
  !must_have_same_datum(time_lock_datum_1, time_lock_datum_2)
}

test must_have_same_datum_fail_when_different_datum_type() {
  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 0, time_lock_nft: #"" },
    }
  let stake_pool_datum =
    StakePoolDatum {
      reward_settings: [],
      policy_id: #"",
      asset_name: #"",
      owner: Signature(#""),
      open_time: 0,
    }
  !must_have_same_datum(time_lock_datum, stake_pool_datum)
}

test add_reward_succeed_normal_case() {
  expect Some(r) = rational.new(1, 100)
  add_reward(1000, r) == 1010
}

test add_reward_succeed_floored_value() {
  expect Some(r) = rational.new(1, 100)
  add_reward(90, r) == 90
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
