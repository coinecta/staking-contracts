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

pub type RewardSetting {
  days_locked: Int,
  percentage_reward: Int,
}

pub type StakePoolDatum {
  time_lock_contract_hash: Hash<Blake2b_224, Script>,
  reward_settings: List<RewardSetting>,
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type StakePoolRedeemer {
  reward_index: Int,
}
