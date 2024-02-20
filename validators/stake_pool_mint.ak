use aiken/transaction.{ScriptContext}
use staking_contracts/datums.{StakePoolDatum, StakePoolRedeemer}
use staking_contracts/stake_nft_mint.{
  StakeNFTMintRedeemer, burn_transaction, mint_transaction,
}
use staking_contracts/stake_pool.{lock_transaction, update_transaction}

validator(time_lock_hash: ByteArray) {
  fn mint(redeemer: StakeNFTMintRedeemer, ctx: ScriptContext) {
    if redeemer.mint {
      mint_transaction(redeemer, ctx, time_lock_hash)?
    } else {
      burn_transaction(ctx, time_lock_hash)?
    }
  }

  fn spend(
    datum: StakePoolDatum,
    redeemer: StakePoolRedeemer,
    ctx: ScriptContext,
  ) -> Bool {
    or {
      update_transaction(datum, ctx)?,
      lock_transaction(datum, redeemer, ctx, time_lock_hash)?,
    }
  }
}
