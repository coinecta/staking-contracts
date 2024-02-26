use aiken/transaction.{ScriptContext}
use staking_contracts/datums.{StakePoolDatum, StakePoolRedeemer}
use staking_contracts/stake_nft_mint.{
  StakeNFTMintRedeemer, burn_transaction, mint_transaction,
}
use staking_contracts/stake_pool.{lock_transaction, update_transaction}

// Spec 1, 2, 2.1
validator(
  // Spec 1.1, 2.2
  time_lock_hash: ByteArray
) {
  // Spec 2.3
  fn mint(redeemer: StakeNFTMintRedeemer, ctx: ScriptContext) {
    // Spec 2.3, 2.5.1
    if redeemer.mint {
      // Spec 2.5
      mint_transaction(redeemer, ctx, time_lock_hash)?
    } else { // Spec 2.6.1
      // Spec 2.6
      burn_transaction(ctx, time_lock_hash)?
    }
  }

  // Spec 1.2
  fn spend(
    datum: StakePoolDatum,
    redeemer: StakePoolRedeemer,
    ctx: ScriptContext,
  ) -> Bool {
    // Spec 1.3
    or {
      // Spec 1.4
      update_transaction(datum, ctx)?,
      // Spec 1.5
      lock_transaction(datum, redeemer, ctx, time_lock_hash)?,
    }
  }
}
