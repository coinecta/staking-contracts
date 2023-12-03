use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction/credential.{Script, VerificationKey}
use aiken/transaction/value.{AssetName, PolicyId}

pub type TimeLockDatum {
  /// POSIX time in second, e.g. 1672843961000
  lock_until: POSIXTime,
  /// Owner's credentials
  owner: VerificationKeyHash,
}

pub type VerificationKeyHash =
  Hash<Blake2b_224, VerificationKey>

pub type POSIXTime =
  Int

pub type ScriptHash =
  Hash<Blake2b_224, Script>

pub type RewardSetting {
  days_locked: Int,
  percentage_reward: Int,
}

pub type StakePoolDatum {
  time_lock_contract_hash: ScriptHash,
  reward_settings: List<RewardSetting>,
  policy_id: PolicyId,
  asset_name: AssetName,
  owner: VerificationKeyHash,
}

pub type StakePoolRedeemer {
  reward_index: Int,
}

pub type StakeProxyDatum {
  owner: VerificationKeyHash,
  days_locked: Int,
  reward_percentage: Int,
  time_lock_contract_hash: ScriptHash,
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub fn to_stake_pool_datum(data: Data) -> StakePoolDatum {
  expect my_datum: StakePoolDatum = data
  my_datum
}

pub fn to_time_lock_datum(data: Data) -> TimeLockDatum {
  expect my_datum: TimeLockDatum = data
  my_datum
}

test must_cast_to_stake_pool_datum() {
  let stake_pool_datum =
    StakePoolDatum {
      time_lock_contract_hash: #"",
      reward_settings: [],
      policy_id: #"",
      asset_name: #"",
      owner: #"",
    }
  let stake_pool_data: Data = stake_pool_datum
  stake_pool_datum == to_stake_pool_datum(stake_pool_data)
}

test must_cast_to_time_lock_datum() {
  let time_lock_datum = TimeLockDatum { lock_until: 0, owner: #"" }
  let time_lock_data: Data = time_lock_datum
  time_lock_datum == to_time_lock_datum(time_lock_data)
}
