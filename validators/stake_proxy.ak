use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list.{find}
use aiken/math/rational
use aiken/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext, Spend,
  Transaction, TransactionId,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{
  add, from_lovelace, from_minted_value, quantity_of, to_minted_value, zero,
}
use staking_contracts/datums.{
  Destination, LockDatum, RewardSetting, StakePoolDatum, StakeProxyDatum,
  TimeLockDatum, to_time_lock_datum,
}
use staking_contracts/utils.{
  add_reward, hour_millis, must_be_locked_until, must_have_exactly_one_output,
}
use sundae/multisig.{Signature, satisfied}

validator(time_lock_hash: ByteArray) {
  fn stake_proxy(
    datum: StakeProxyDatum,
    _redeemer: Void,
    ctx: ScriptContext,
  ) -> Bool {
    or {
      refund_transaction(datum, ctx)?,
      lock_transaction(datum, ctx, time_lock_hash)?,
    }
  }
}

fn refund_transaction(datum: StakeProxyDatum, ctx: ScriptContext) -> Bool {
  when ctx.purpose is {
    //The proxy needs to be spent in a manual refund
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

fn lock_transaction(
  datum: StakeProxyDatum,
  ctx: ScriptContext,
  time_lock_hash: ByteArray,
) -> Bool {
  when ctx.purpose is {
    //The proxy needs to be spend in a locking transaction
    Spend(my_output_reference) ->
      is_proper_locking_tx(my_output_reference, datum, ctx, time_lock_hash)?
    _ -> False
  }
}

//Ensures that tokens are locked for the duration the user requests
//and that the reward is matching the expectation
fn is_proper_locking_tx(
  my_output_reference: OutputReference,
  datum: StakeProxyDatum,
  ctx: ScriptContext,
  time_lock_hash: ByteArray,
) {
  //Find the input this validator is attached to
  expect Some(self) =
    ctx.transaction.inputs
      |> transaction.find_input(my_output_reference)
  //Find the output locking the staked tokens + reward and extract its datum
  let time_lock_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(time_lock_hash)
  expect Some(time_lock_output) = time_lock_outputs |> list.at(0)
  expect InlineDatum(time_lock_output_datum) = time_lock_output.datum
  let time_lock_datum = to_time_lock_datum(time_lock_output_datum)

  //We assume all assets matching the policy_id+asset_name are to be staked
  let staked_tokens =
    self.output.value
      |> quantity_of(datum.policy_id, datum.asset_name)

  //The amount of tokens locked, should be staked + reward
  let locked_tokens =
    time_lock_output.value
      |> quantity_of(datum.policy_id, datum.asset_name)

  //Find minted stake key
  let minted = from_minted_value(ctx.transaction.mint)

  let minted_policy_id = bytearray.take(time_lock_datum.extra.time_lock_key, 28)

  let minted_asset_name =
    bytearray.drop(time_lock_datum.extra.time_lock_key, 28)

  //Make sure the minted key is using the expected policy_id
  let correct_stake_key_policy_id = minted_policy_id == datum.key_policy_id

  //Make sure only 1 is minted
  let correct_key_minted =
    quantity_of(minted, minted_policy_id, minted_asset_name) == 1

  //Make sure the key is minted into the users' wallet
  expect Some(_key_minted_to_user) =
    ctx.transaction.outputs
      |> find(
           fn(o) {
             quantity_of(o.value, minted_policy_id, minted_asset_name) == 1 && o.address == datum.destination.address && o.datum == datum.destination.datum
           },
         )

  //Ensure locked tokens is staked + reward
  let correct_locked_tokens =
    locked_tokens == add_reward(staked_tokens, datum.reward_multiplier)

  and {
    //Ensure only one time lock output to avoid unexpected results
    must_have_exactly_one_output(time_lock_outputs)?,
    correct_stake_key_policy_id?,
    //Make sure the time lock does not lock the assets too long
    must_be_locked_until(
      ctx.transaction.validity_range,
      time_lock_output,
      datum.ms_locked,
      hour_millis,
    )?,
    correct_locked_tokens?,
    correct_key_minted?,
  }
}

test stake_proxy_lock_funds() {
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
      decimals: 0,
      policy_id: #"00000000000000000000000000000000000000000000000000000000",
      asset_name: #"000000000000",
      reward_settings: [
        RewardSetting { ms_locked: 86_400_000, reward_multiplier: reward },
      ],
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
      key_policy_id: #"00000000000000000000000000000000000000000000000000000011",
      key_img_url: "https://my-stake-key-img.com/img.png",
    }

  let current_time = 0
  let later_time = 2 * hour_millis

  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum {
        lock_until: current_time + hour_millis + 86_400_000,
        time_lock_key: #"00000000000000000000000000000000000000000000000000000011",
      },
    }

  let time_lock_data: Data = time_lock_datum

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

  let user_output =
    Output {
      address: stake_proxy_datum.destination.address,
      value: from_lovelace(100000)
        |> add(stake_proxy_datum.key_policy_id, #"", 1),
      reference_script: None,
      datum: stake_proxy_datum.destination.datum,
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
      purpose: Spend(stake_proxy_output_reference),
      transaction: transaction.placeholder()
        |> fn(transaction) {
             Transaction {
               ..transaction,
               inputs: [stake_pool_input, stake_proxy_input],
               outputs: [new_stake_pool_output, time_lock_output, user_output],
               mint: zero()
                 |> add(stake_proxy_datum.key_policy_id, #"", 1)
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
  lock_transaction(stake_proxy_datum, context, time_lock_hash)
}
