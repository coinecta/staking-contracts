use aiken/bytearray.{drop, take}
use aiken/transaction.{ScriptContext, Spend}
use aiken/transaction/value.{MintedValue, from_minted_value, quantity_of}
use staking_contracts/datums.{TimeLockDatum}
use staking_contracts/utils.{must_start_after}

validator {
  fn time_lock(datum: TimeLockDatum, _redeemer: Void, ctx: ScriptContext) {
    when ctx.purpose is {
      //This utxo can only be spend by its owner and after the unlock time has passed
      Spend(_) -> and {
          nft_is_burned(ctx.transaction.mint, datum.extra.time_lock_nft),
          must_start_after(
            ctx.transaction.validity_range,
            datum.extra.lock_until,
          ),
        }
      _ -> False
    }
  }
}

fn nft_is_burned(minted: MintedValue, nft: ByteArray) {
  let minted_value = from_minted_value(minted)
  let minted_amount = minted_value |> quantity_of(take(nft, 28), drop(nft, 28))
  minted_amount == -1
}
