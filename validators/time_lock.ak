use aiken/bytearray.{drop, take}
use aiken/transaction.{ScriptContext, Spend}
use aiken/transaction/value.{MintedValue, from_minted_value, quantity_of}
use staking_contracts/datums.{TimeLockDatum}
use staking_contracts/utils.{must_start_after}

// Spec 3, 3.1
validator {
  // Spec 3.2
  fn time_lock(datum: TimeLockDatum, _redeemer: Void, ctx: ScriptContext) {
    when ctx.purpose is {
      // Spec 3.3.1
      //This utxo can only be spend by its owner and after the unlock time has passed
      Spend(_) -> and {
          // Spec 3.3.2
          nft_is_burned(ctx.transaction.mint, datum.extra.time_lock_nft),
          // Spec 3.3.3
          must_start_after(
            ctx.transaction.validity_range,
            datum.extra.lock_until,
          ),
        }
      _ -> False
    }
  }
}

// Spec 3.3.2 - n.b. minted comes from transaction.mint, and nft comes from datum.extra.time_lock_nft
fn nft_is_burned(minted: MintedValue, nft: ByteArray) {
  let minted_value = from_minted_value(minted)
  // Spec 3.3.2
  let minted_amount = minted_value
    |> quantity_of( // Spec 3.3.2.3
      take(nft, 28), // Spec 3.3.2.1
      drop(nft, 28)  // Spec 3.3.2.2
    )
  // Spec 3.3.2.4
  minted_amount == -1
}
