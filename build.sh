set -e

aiken build

TIME_LOCK_HASH="581c$(aiken blueprint hash -v time_lock.time_lock)"
aiken blueprint apply -v stake_pool.stake_pool $TIME_LOCK_HASH > tmp
mv tmp plutus.json

STAKE_POOL_HASH="581c$(aiken blueprint hash -v stake_pool.stake_pool)"
aiken blueprint apply -v stake_proxy.stake_proxy $TIME_LOCK_HASH > tmp
mv tmp plutus.json

STAKE_PROXY_HASH="581c$(aiken blueprint hash -v stake_proxy.stake_proxy)"
aiken blueprint apply -v stake_key_mint.stake_key_mint $TIME_LOCK_HASH > tmp
mv tmp plutus.json
aiken blueprint apply -v stake_key_mint.stake_key_mint $STAKE_POOL_HASH > tmp
mv tmp plutus.json
aiken blueprint apply -v stake_key_mint.stake_key_mint $STAKE_PROXY_HASH > tmp
mv tmp plutus.json