use aiken/dict.{Dict}
use aiken/hash.{Blake2b_224, Hash}
use aiken/math/rational.{Rational}
use aiken/time.{PosixTime}
use aiken/transaction.{Datum}
use aiken/transaction/credential.{Address, Script, VerificationKey}
use aiken/transaction/value.{AssetName, PolicyId}
use sundae/multisig.{MultisigScript, Signature}

//Prefix of the reference nft asset id according to CIP-68
pub const reference_prefix = #"000643b0"

//Prefix of the nft asset id according to CIP-68
pub const stake_nft_prefix = #"000de140"

pub type LockDatum {
  /// POSIX time in second, e.g. 1672843961000
  lock_until: PosixTime,
  /// Owner's credentials
  time_lock_nft: ByteArray,
}

pub type TimeLockDatum {
  //Metadata fields holding name, img etc for the stake nft following CIP-25
  metadata: Dict<ByteArray, ByteArray>,
  //Following on chain metadata standard in CIP-68
  version: Int,
  //Data defining the time the assets are to be locked and how to unlock
  extra: LockDatum,
}

pub type VerificationKeyHash =
  Hash<Blake2b_224, VerificationKey>

pub type ScriptHash =
  Hash<Blake2b_224, Script>

pub type RewardSetting {
  //Amount of milliseconds the tokens need to be locked
  ms_locked: Int,
  //Percentage the user gets as a reward for locking
  reward_multiplier: Rational,
}

pub type StakePoolDatum {
  //List of rewardsettings that are enabled by the stakepool owner
  reward_settings: List<RewardSetting>,
  //Policy id of the asset in the stake pool
  policy_id: PolicyId,
  //Asset name of the asset in the stake pool
  asset_name: AssetName,
  //Owner script that is allowed to change settings on the pool or remove unused assets
  owner: MultisigScript,
  //Earliest time the pool can distribute rewards
  open_time: PosixTime,
}

pub type StakePoolRedeemer {
  //Index of the reward setting to be used ina locking tx.
  // Spec 1.5.8
  reward_index: Int,
}

pub type Destination {
  //Address of the destination
  address: Address,
  //Datum of the destination
  datum: Datum,
}

pub type StakeProxyDatum {
  //Users' script defining who can initiate a refund.
  owner: MultisigScript,
  //Destination which should receive the stake nft
  destination: Destination,
  //Amount of milliseconds the user wished to lock his tokens
  ms_locked: Int,
  //The reward percentage the user expects for locking his tokens
  reward_multiplier: Rational,
  //Policy id of the asset the user wants to stake
  policy_id: PolicyId,
  //Asset name of the asset the user wants to stake
  asset_name: AssetName,
  //Amount of assets to stake
  asset_amount: Int,
  //Lovelace amount to put in timelock
  lovelace_amount: Int,
  //Policy id the user expects the stake nft to be minted with
  nft_policy_id: PolicyId,
}

pub fn to_stake_pool_datum(data: Data) -> StakePoolDatum {
  expect my_datum: StakePoolDatum = data
  my_datum
}

pub fn to_stake_proxy_datum(data: Data) -> StakeProxyDatum {
  expect my_datum: StakeProxyDatum = data
  my_datum
}

pub fn to_time_lock_datum(data: Data) -> TimeLockDatum {
  expect my_datum: TimeLockDatum = data
  my_datum
}

test must_cast_to_stake_pool_datum() {
  let stake_pool_datum =
    StakePoolDatum {
      reward_settings: [],
      policy_id: #"",
      asset_name: #"",
      owner: Signature(#""),
      open_time: 0,
    }
  let stake_pool_data: Data = stake_pool_datum
  stake_pool_datum == to_stake_pool_datum(stake_pool_data)
}

test must_cast_to_time_lock_datum() {
  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum { lock_until: 0, time_lock_nft: #"" },
    }
  let time_lock_data: Data = time_lock_datum
  time_lock_datum == to_time_lock_datum(time_lock_data)
}
