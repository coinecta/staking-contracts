use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list.{at, length}
use aiken/math/rational
use aiken/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext, Spend,
  Transaction, TransactionId,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{add, from_lovelace, to_minted_value, zero}
use staking_contracts/datums.{
  Destination, LockDatum, RewardSetting, StakePoolDatum, StakePoolRedeemer,
  StakeProxyDatum, TimeLockDatum, to_time_lock_datum,
}
use staking_contracts/utils.{
  add_reward, filter_inputs_by_credential, hour_millis, must_be_locked_until,
  must_have_exactly_one_output,
}
use sundae/multisig.{Signature, satisfied}

pub fn update_transaction(datum: StakePoolDatum, ctx: ScriptContext) -> Bool {
  when ctx.purpose is {
    //Ensure the utxo is spent by the owner
    Spend(_) ->
      satisfied(
        datum.owner,
        ctx.transaction.extra_signatories,
        ctx.transaction.validity_range,
        ctx.transaction.withdrawals,
      )?
    _ -> False
  }
}

pub fn lock_transaction(
  datum: StakePoolDatum,
  redeemer: StakePoolRedeemer,
  ctx: ScriptContext,
  time_lock_hash: ByteArray,
) -> Bool {
  when ctx.purpose is {
    //Ensure the utxo is spent in a valid locking tx
    Spend(my_output_reference) ->
      is_proper_locking_tx(
        my_output_reference,
        datum,
        redeemer,
        ctx,
        time_lock_hash,
      )?
    _ -> False
  }
}

fn is_proper_locking_tx(
  my_output_reference: OutputReference,
  datum: StakePoolDatum,
  redeemer: StakePoolRedeemer,
  ctx: ScriptContext,
  time_lock_hash: ByteArray,
) {
  expect Finite(lower_bound) =
    ctx.transaction.validity_range.lower_bound.bound_type
  expect lower_bound >= datum.open_time
  //Find the input guarded by this validator
  expect Some(self) =
    ctx.transaction.inputs
      |> transaction.find_input(my_output_reference)

  let self_input = self.output

  //Find amount of inputs with stake pool script, should be exactly 1
  let exactly_one_stake_pool_input =
    length(
      filter_inputs_by_credential(
        ctx.transaction.inputs,
        self_input.address.payment_credential,
      ),
    ) == 1

  //We need to ensure the output of the tx has the same validator attached
  expect ScriptCredential(self_script) = self_input.address.payment_credential
  let self_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(self_script)
  expect Some(self_output) = self_outputs |> at(0)

  expect self_input.address == self_output.address
  //The output needs to include a utxo with time lock validator
  let time_lock_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(time_lock_hash)
  expect Some(time_lock) = time_lock_outputs |> at(0)

  expect InlineDatum(time_lock_data) = time_lock.datum

  let time_lock_datum = to_time_lock_datum(time_lock_data)

  //We use the reward setting as indicated by the submitter of the transaction
  expect Some(reward_setting) =
    datum.reward_settings |> at(redeemer.reward_index)
  //Find out current stake_pool token quantity
  let stake_pool_size =
    self_input.value
      |> value.quantity_of(datum.policy_id, datum.asset_name)

  //Find stake_pool token quantity in output
  let new_stake_pool_size =
    self_output.value
      |> value.quantity_of(datum.policy_id, datum.asset_name)

  //Difference between old and new quantity is equal to the reward to the staker
  let reward = stake_pool_size - new_stake_pool_size

  //The locked amount in the time lock output
  let locked_amount =
    time_lock.value
      |> value.quantity_of(datum.policy_id, datum.asset_name)

  //The staked amount is deduced from the locked amount and the reward
  let staked_amount = locked_amount - reward

  //Ensure the locked amount matches the reward setting
  let correct_locked_amount =
    locked_amount == add_reward(staked_amount, reward_setting.reward_multiplier)

  //Make sure no other assets have been altered in the stake pool output compared to the input
  let correct_output_value =
    value.without_lovelace(self_input.value) == add(
      value.without_lovelace(self_output.value),
      datum.policy_id,
      datum.asset_name,
      reward,
    )

  //Allow higher lovelace amount to support increase of minutxo
  expect
    value.lovelace_of(self_input.value) <= value.lovelace_of(self_output.value)
  //Make sure settings have not been altered
  let same_datum = InlineDatum(datum) == self_output.datum

  let one_stake_nft_minted =
    1 == value.quantity_of(
      value.from_minted_value(ctx.transaction.mint),
      bytearray.take(time_lock_datum.extra.time_lock_nft, 28),
      bytearray.drop(time_lock_datum.extra.time_lock_nft, 28),
    )

  expect bytearray.take(time_lock_datum.extra.time_lock_nft, 28) == self_script
  and {
    one_stake_nft_minted?,
    exactly_one_stake_pool_input?,
    //Ensure exactly one stake pool output
    must_have_exactly_one_output(self_outputs)?,
    //Ensure exactly one time lock output
    must_have_exactly_one_output(time_lock_outputs)?,
    same_datum?,
    correct_locked_amount?,
    //Ensure that the time lock does not expire too soon
    must_be_locked_until(
      ctx.transaction.validity_range,
      time_lock,
      reward_setting.ms_locked,
      hour_millis,
    )?,
    correct_output_value?,
  }
}

test stake_pool_lock_funds() {
  let time_lock_hash =
    #"550cc5a9682bcbbe5583f1006624000032b4d8f4ddd6f37623462ff9"

  let stake_pool_hash =
    #"7a8a80f13e296da14c3c4e379e1c270ffabb2740a28e983acf75275f"

  let stake_proxy_hash =
    #"dc404ed342f5bc8344c8e2d21da7a45b8e0f70b5364ee4fda57dae75"
  expect Some(reward) = rational.new(1, 100)
  let stake_pool_datum =
    StakePoolDatum {
      owner: Signature(
        #"00000000000000000000000000000000000000000000000000000000",
      ),
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      reward_settings: [
        RewardSetting { ms_locked: 86_400_000, reward_multiplier: reward },
      ],
      open_time: 0,
    }

  let stake_proxy_datum =
    StakeProxyDatum {
      owner: Signature(
        #"00000000000000000000000000000000000000000000000000000000",
      ),
      destination: Destination {
        address: Address {
          payment_credential: VerificationKeyCredential(
            #"00000000000000000000000000000000000000000000000000000000",
          ),
          stake_credential: None,
        },
        datum: NoDatum,
      },
      ms_locked: 86_400_000,
      reward_multiplier: reward,
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      asset_amount: 1_000_000,
      lovelace_amount: 2_000_000,
      nft_policy_id: stake_pool_hash,
    }

  let current_time = 0
  let later_time = hour_millis

  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum {
        lock_until: later_time + 86_400_000,
        time_lock_nft: bytearray.concat(stake_pool_hash, #"000000000000"),
      },
    }
  let time_lock_data: Data = time_lock_datum

  let redeemer = StakePoolRedeemer { reward_index: 0 }
  let stake_pool_output_reference =
    OutputReference { transaction_id: TransactionId(""), output_index: 0 }

  let stake_pool_output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(stake_pool_hash),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_000_000_000,
           ),
      datum: InlineDatum(stake_pool_datum),
      reference_script: None,
    }

  let stake_pool_input =
    Input {
      output_reference: stake_pool_output_reference,
      output: stake_pool_output,
    }

  let stake_proxy_output_reference =
    OutputReference { transaction_id: TransactionId(""), output_index: 1 }

  let stake_proxy_output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(stake_proxy_hash),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_000_000,
           ),
      datum: InlineDatum(stake_proxy_datum),
      reference_script: None,
    }
  let stake_proxy_input =
    Input {
      output_reference: stake_proxy_output_reference,
      output: stake_proxy_output,
    }

  let new_stake_pool_output =
    Output {
      ..stake_pool_output,
      value: //address: Address { payment_credential: #"00000000000000000000000000000000000000000000000000000010", stake_credential: None },
      from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             999_990_000,
           ),
    }

  //datum: stake_pool_datum,
  //reference_script: None,
  let time_lock_output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(time_lock_hash),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(
             #"00000000000000000000000000000000000000000000000000000000",
             #"000000000000",
             1_010_000,
           ),
      datum: InlineDatum(time_lock_data),
      reference_script: None,
    }
  let context =
    ScriptContext {
      purpose: Spend(stake_pool_output_reference),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction {
               ..transaction,
               inputs: [stake_pool_input, stake_proxy_input],
               outputs: [new_stake_pool_output, time_lock_output],
               mint: zero()
                 |> add(stake_pool_hash, #"000000000000", 1)
                 |> to_minted_value(),
               validity_range: Interval {
                 lower_bound: IntervalBound {
                   bound_type: Finite(current_time),
                   is_inclusive: True,
                 },
                 upper_bound: IntervalBound {
                   bound_type: Finite(later_time),
                   is_inclusive: True,
                 },
               },
             }
           },
    }
  lock_transaction(stake_pool_datum, redeemer, context, time_lock_hash)
}
