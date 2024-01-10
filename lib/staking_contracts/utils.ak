use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite}
use aiken/list.{has, length}
use aiken/math
use aiken/math/rational.{Rational}
use aiken/string
use aiken/time.{PosixTime}
use aiken/transaction.{InlineDatum, Output, Transaction, ValidityRange}
use staking_contracts/datums.{
  LockDatum, StakePoolDatum, TimeLockDatum, VerificationKeyHash,
  to_time_lock_datum,
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

pub fn add_reward(amount: Int, reward: Rational) -> Int {
  rational.floor(
    rational.mul(
      rational.from_int(amount),
      rational.add(rational.from_int(1), reward),
    ),
  )
}

pub const day_millis = 86_400_000

//pub const day_millis = 3_600_000

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
  let lock_expiration_time =
    to_time_lock_datum(time_lock_datum).extra.lock_until
  and {
    //This ensures for the user that the assets are not locked longer than expected
    when range.lower_bound.bound_type is {
      Finite(tx_earliest_time) ->
        tx_earliest_time + days_to_be_locked * day_millis + buffer >= lock_expiration_time
      _ -> False
    }?,
    //This ensures assets are locked for at least the required amount as configured in the stake pool
    when range.upper_bound.bound_type is {
      Finite(tx_latest_time) ->
        tx_latest_time + days_to_be_locked * day_millis - buffer <= lock_expiration_time
      _ -> False
    }?,
  }
}

pub fn must_start_after(range: ValidityRange, lock_expiration_time: PosixTime) {
  when range.lower_bound.bound_type is {
    Finite(tx_earliest_time) -> lock_expiration_time <= tx_earliest_time
    _ -> False
  }?
}

pub fn abbreviated_amount(amount: Int, decimals: Int) -> ByteArray {
  let amount_dec = amount / math.pow(10, decimals)
  let quadrillions = amount_dec / 1_000_000_000_000
  if quadrillions > 0 {
    if quadrillions > 999 {
      "***Q"
    } else {
      bytearray.from_string(string.concat(string.from_int(quadrillions), @"Q"))
    }
  } else {
    let billions = amount_dec / 1_000_000_000
    if billions > 0 {
      bytearray.from_string(string.concat(string.from_int(billions), @"B"))
    } else {
      let millions = amount_dec / 1_000_000
      if millions > 0 {
        bytearray.from_string(string.concat(string.from_int(millions), @"M"))
      } else {
        let thousands = amount_dec / 1_000
        if thousands > 0 {
          bytearray.from_string(string.concat(string.from_int(thousands), @"K"))
        } else {
          bytearray.from_string(string.from_int(amount_dec))
        }
      }
    }
  }
}

//Taken from https://stackoverflow.com/questions/7136385/calculate-day-number-from-an-unix-timestamp-in-a-math-way
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

test abbreviated_amount_0_point_666_tokens_abreviates_to_0() {
  let amount = 666_666_666_666
  let decimals = 12
  abbreviated_amount(amount, decimals) == "0"
}

test abbreviated_amount_666_tokens_abreviates_to_666() {
  let amount = 666_666_666_666
  let decimals = 9
  abbreviated_amount(amount, decimals) == "666"
}

test abbreviated_amount_666_thousand_tokens_abreviates_to_666K() {
  let amount = 666_666_666_666
  let decimals = 6
  abbreviated_amount(amount, decimals) == "666K"
}

test abbreviated_amount_666_million_tokens_abreviates_to_666M() {
  let amount = 666_666_666_666
  let decimals = 3
  abbreviated_amount(amount, decimals) == "666M"
}

test abbreviated_amount_666_billion_tokens_abreviates_to_666B() {
  let amount = 666_666_666_666_000
  let decimals = 3
  abbreviated_amount(amount, decimals) == "666B"
}

test abbreviated_amount_666_quadrillion_tokens_abreviates_to_666Q() {
  let amount = 666_666_666_666_000_000
  let decimals = 3
  abbreviated_amount(amount, decimals) == "666Q"
}

test abbreviated_amount_ridiculous_amount_should_be_3starQ() {
  let amount = 666_666_666_666_000_000
  let decimals = 0
  abbreviated_amount(amount, decimals) == "***Q"
}

test must_have_same_datum_succeed_when_same_datum() {
  let time_lock_datum_1 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 0, time_lock_key: #"" },
    }
  let time_lock_datum_2 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 0, time_lock_key: #"" },
    }
  must_have_same_datum(time_lock_datum_1, time_lock_datum_2)
}

test must_have_same_datum_fail_when_different_datum() {
  let time_lock_datum_1 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 0, time_lock_key: #"" },
    }
  let time_lock_datum_2 =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 1, time_lock_key: #"" },
    }
  !must_have_same_datum(time_lock_datum_1, time_lock_datum_2)
}

test must_have_same_datum_fail_when_different_datum_type() {
  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 0, time_lock_key: #"" },
    }
  let stake_pool_datum =
    StakePoolDatum {
      decimals: 0,
      reward_settings: [],
      policy_id: #"",
      asset_name: #"",
      owner: #"",
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
