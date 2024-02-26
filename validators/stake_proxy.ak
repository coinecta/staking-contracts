use aiken/bytearray.{drop, take}
use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list.{length}
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
  add_reward, filter_inputs_by_credential, hour_millis, must_be_locked_until,
  must_contain_asset, must_have_exactly_one_output,
}
use sundae/multisig.{Signature, satisfied}

// Spec 4, 4.1
validator(time_lock_hash: ByteArray, batcher_certificate) {
  // Spec 4.2
  fn stake_proxy(
    datum: StakeProxyDatum,
    _redeemer: Void,
    ctx: ScriptContext,
  ) -> Bool {
    // Spec 4.3
    or {
      // Spec 4.3.1
      refund_transaction(datum, ctx)?,
      // Spec 4.3.2
      lock_transaction(datum, ctx, time_lock_hash, batcher_certificate)?,
    }
  }
}

// Spec 4.3.1
fn refund_transaction(datum: StakeProxyDatum, ctx: ScriptContext) -> Bool {
  when ctx.purpose is {
    //The proxy needs to be spent in a manual refund
    // Spec 4.3.1.1
    Spend(_) ->
      // Spec 4.3.1.2
      satisfied(
        datum.owner,
        ctx.transaction.extra_signatories,
        ctx.transaction.validity_range,
        ctx.transaction.withdrawals,
      )?
    _ -> False
  }
}

// Spec 4.3.2
fn lock_transaction(
  datum: StakeProxyDatum,
  ctx: ScriptContext,
  time_lock_hash: ByteArray,
  batcher_certificate: ByteArray,
) -> Bool {
  when ctx.purpose is {
    //The proxy needs to be spend in a locking transaction by a certified batcher
    // Spec 4.3.2.1
    Spend(my_output_reference) -> and {
        // Spec 4.3.2.3 - 
        is_proper_locking_tx(my_output_reference, datum, ctx, time_lock_hash)?,
        // Spec 4.3.2.2
        must_contain_asset(ctx.transaction.outputs, batcher_certificate)?,
      }
    _ -> False
  }
}

//Ensures that tokens are locked for the duration the user requests
//and that the reward is matching the expectation
// Spec 4.3.2
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

  //Find amount of inputs with stake proxy script, should be exactly 1
  // Spec 4.3.2.3 - n.b. included in the `and` below
  let exactly_one_stake_proxy_input =
    length(
      filter_inputs_by_credential(
        ctx.transaction.inputs,
        self.output.address.payment_credential,
      ),
    ) == 1

  //Find the output locking the staked tokens + reward and extract its datum
  // Spec 4.3.2.4 - n.b. existence, uniqueness is checked below
  let time_lock_outputs =
    ctx.transaction.outputs
      |> transaction.find_script_outputs(time_lock_hash)
  // Spec 4.3.2.4 - n.b. existence, uniqueness is checked below
  expect Some(time_lock_output) = time_lock_outputs |> list.at(0)
  // Spec 4.3.2.5
  expect InlineDatum(time_lock_output_datum) = time_lock_output.datum
  let time_lock_datum = to_time_lock_datum(time_lock_output_datum)

  //Time lock should have lovelace, staked asset + reference nft
  // Spec 4.3.2.6
  expect list.length(value.flatten(time_lock_output.value)) == 3
  //Time lock should have at least 2 ADA - n.b. comment incorrect
  // Spec 4.3.2.7
  expect value.lovelace_of(time_lock_output.value) == datum.lovelace_amount
  //We assume all assets matching the policy_id+asset_name are to be staked
  let staked_tokens = datum.asset_amount

  //The amount of tokens locked, should be staked + reward
  // Spec 4.3.2.8
  let locked_tokens =
    time_lock_output.value
      |> quantity_of(datum.policy_id, datum.asset_name)

  //Find minted stake nft
  let minted = from_minted_value(ctx.transaction.mint)

  // Spec 4.3.2.9
  let minted_policy_id = bytearray.take(time_lock_datum.extra.time_lock_nft, 28)

  // Spec 4.3.2.10
  let minted_asset_name =
    bytearray.drop(time_lock_datum.extra.time_lock_nft, 28)

  //Make sure the minted nft is using the expected policy_id
  // Spec 4.3.2.11 - n.b. included in the `and` below
  let correct_stake_nft_policy_id = minted_policy_id == datum.nft_policy_id

  //Make sure only 1 is minted
  // Spec 4.3.2.12 - n.b. included in the `and` below
  let correct_nft_minted =
    quantity_of(minted, minted_policy_id, minted_asset_name) == 1

  //There should be 1 destination output
  // Spec 4.3.2.13 - "There must be exactly one"
  expect [destination_output] =
    // Spec 4.3.2.13 - "output"
    ctx.transaction.outputs
      // Spec 4.3.2.13 - "such that"
      |> list.filter(
           fn(o) {
             // Spec 4.3.2.13 - "the address of the output is equal to datum.destination.address"
             o.address == datum.destination.address
             // Spec 4.3.2.13 - "And the datum of the output is equal to datum.destination.datum"
             && o.datum == datum.destination.datum
           },
         )
  // Spec 4.3.2.13 - n.b. Here, we compute the difference between the input and the two outputs sent to the user
  let lovelace_cost =
    value.lovelace_of(self.output.value) - (
      value.lovelace_of(time_lock_output.value) + value.lovelace_of(
        destination_output.value,
      )
    )
  // Spec 4.3.2.13 - and here we enforce that that difference is exactly 2 ada
  expect lovelace_cost == 2_000_000
  
  //The value of the proxy input should match the value of time_lock+destination
  //taking the lovelace cost (tx fee + sequencer fee) and reward and minted nft's into account
  // Spec 4.3.2.15 + 4.3.2.16
  let combined_user_value =
    // Spec 4.3.2.15.1 - "Let relevant outputs be the sum of the time lock output"
    time_lock_output.value
    // Spec 4.3.2.15.2 - "The destination output"
      |> value.merge(destination_output.value)
      // Spec 4.3.2.15.3 - "the 2 million lovelace fee"
      |> value.merge(value.from_lovelace(lovelace_cost))
      // Spec 4.3.2.16.1 - "Let relevant inputs be the sum of the transaction mint" (n.b. negated because we check for equality with zero, rather than checking for equality)
      |> value.merge(value.negate(value.from_minted_value(ctx.transaction.mint)))
      // Spec 4.3.2.16.2 - "the total value on the stake proxy input being spent" (n.b. negated because ...)
      |> value.merge(value.negate(self.output.value))
      // Spec 4.3.2.16.3 - "the reward token from the stake pool"
      |> value.merge(
           value.negate(
             value.from_asset(
               datum.policy_id,
               datum.asset_name,
               // Spec 4.3.2.16.3 "calculated as the difference between the tokens on the time lock output and the amount declared in the datum"
               locked_tokens - staked_tokens,
             ),
           ),
         )
  // Spec 4.3.2.17 - n.b. we check equal to zero, because we subtracted off `relevant_outputs` above
  expect combined_user_value == value.zero()
  // Spec 4.3.2.18
  expect
    quantity_of(destination_output.value, minted_policy_id, minted_asset_name) == 1
  //Ensure locked tokens is staked + reward
  // Spec 4.3.2.20 - n.b. included in the `and` below
  let correct_locked_tokens =
    locked_tokens == add_reward(staked_tokens, datum.reward_multiplier)

  and {
    // Spec 4.3.2.3
    exactly_one_stake_proxy_input?,
    //Ensure only one time lock output to avoid unexpected results
    // Spec 4.3.2.4 - n.b. uniqueness
    must_have_exactly_one_output(time_lock_outputs)?,
    // Spec 4.3.2.11
    correct_stake_nft_policy_id?,
    //Make sure the time lock does not lock the assets too long
    // Spec 4.3.2.21
    must_be_locked_until(
      ctx.transaction.validity_range,
      time_lock_output,
      datum.ms_locked,
      hour_millis,
    )?,
    // Spec 4.3.2.20
    correct_locked_tokens?,
    // Spec 4.3.2.12
    correct_nft_minted?,
  }
}

test stake_proxy_lock_funds() {
  let time_lock_hash =
    #"550cc5a9682bcbbe5583f1006624000032b4d8f4ddd6f37623462ff9"

  let stake_pool_hash =
    #"7a8a80f13e296da14c3c4e379e1c270ffabb2740a28e983acf75275f"

  let stake_proxy_hash =
    #"dc404ed342f5bc8344c8e2d21da7a45b8e0f70b5364ee4fda57dae75"

  let batcher_certificate =
    #"00000000000000000000000000000000000000000000000000000011000643b06921e91f6af4b4eef9d1a9b55ed75c4e09243b3c67edd1f013230d75"

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
      nft_policy_id: #"00000000000000000000000000000000000000000000000000000011",
    }

  let current_time = 0
  let later_time = hour_millis

  let time_lock_datum =
    TimeLockDatum {
      metadata: dict.new(),
      version: 1,
      extra: LockDatum {
        lock_until: later_time + 86_400_000,
        time_lock_nft: #"00000000000000000000000000000000000000000000000000000011",
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

  let batcher_output =
    Output {
      address: Address {
        payment_credential: VerificationKeyCredential(#""),
        stake_credential: None,
      },
      value: from_lovelace(2000000)
        |> add(batcher_certificate |> take(28), batcher_certificate |> drop(28), 1),
      datum: NoDatum,
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
      value: from_lovelace(6_000_000)
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
      value: from_lovelace(2_000_000)
        |> add(stake_proxy_datum.nft_policy_id, #"", 1),
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
           )
        |> add(
             #"00000000000000000000000000000000000000000000000000000011",
             #"00000000",
             1,
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
               outputs: [
                 new_stake_pool_output,
                 time_lock_output,
                 user_output,
                 batcher_output,
               ],
               mint: zero()
                 |> add(stake_proxy_datum.nft_policy_id, #"", 1)
                 |> add(stake_proxy_datum.nft_policy_id, #"00000000", 1)
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
  lock_transaction(
    stake_proxy_datum,
    context,
    time_lock_hash,
    batcher_certificate,
  )
}
