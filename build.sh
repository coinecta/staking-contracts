set -e

aiken build

BATCHER_CERTIFICATE="583C00000000000000000000000000000000000000000000000000000011000643B06921E91F6AF4B4EEF9D1A9B55ED75C4E09243B3C67EDD1F013230D75"

TIME_LOCK_HASH="581c$(aiken blueprint hash -v time_lock.time_lock)"
aiken blueprint apply -v stake_pool_mint.spend $TIME_LOCK_HASH > tmp
mv tmp plutus.json
aiken blueprint apply -v stake_pool_mint.mint $TIME_LOCK_HASH > tmp
mv tmp plutus.json

aiken blueprint apply -v stake_proxy.stake_proxy $TIME_LOCK_HASH > tmp
mv tmp plutus.json
aiken blueprint apply -v stake_proxy.stake_proxy $BATCHER_CERTIFICATE > tmp
mv tmp plutus.json