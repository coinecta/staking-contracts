set -e

echo

echo "Git commit       = $(git rev-parse HEAD)"
echo "Aiken Version    = $(aiken --version)"

echo
SHA256=$(cat validators/stake_pool_mint.ak | sha256sum | cut -f 1 -d ' ')
echo "validators/stake_pool_mint.ak                      = ${SHA256}"
SHA256=$(cat validators/stake_proxy.ak | sha256sum | cut -f 1 -d ' ')
echo "validators/stake_proxy.ak                          = ${SHA256}"
SHA256=$(cat validators/time_lock.ak | sha256sum | cut -f 1 -d ' ')
echo "validators/time_lock.ak                            = ${SHA256}"
SHA256=$(cat lib/staking_contracts/datums.ak | sha256sum | cut -f 1 -d ' ')
echo "lib/staking_contracts/datums.ak                    = ${SHA256}"
SHA256=$(cat lib/staking_contracts/stake_nft_mint.ak | sha256sum | cut -f 1 -d ' ')
echo "lib/staking_contracts/stake_nft_mint.ak            = ${SHA256}"
SHA256=$(cat lib/staking_contracts/stake_pool.ak | sha256sum | cut -f 1 -d ' ')
echo "lib/staking_contracts/stake_pool.ak                = ${SHA256}"
SHA256=$(cat lib/staking_contracts/utils.ak | sha256sum | cut -f 1 -d ' ')
echo "lib/staking_contracts/utils.ak                     = ${SHA256}"

echo

aiken build &> /dev/null

TIME_LOCK_HASH=$(cat plutus.json | jq --raw-output '.validators[] | select(.title == "time_lock.time_lock") | .hash')
TIME_LOCK_ADDR=$(aiken blueprint address -v time_lock.time_lock 2> /dev/null)
BATCHER_POLICY="f9c811825adb28f42d82391b900ca6962fa94a1d51739fbaa52f4b06"
BATCHER_ASSET_NAME="434e43545f4345525449464943415445"
BATCHER_CERTIFICATE="${BATCHER_POLICY}${BATCHER_ASSET_NAME}"

aiken blueprint apply -v stake_pool_mint.mint "581c${TIME_LOCK_HASH}" 2> /dev/null > tmp
mv tmp plutus.json
aiken blueprint apply -v stake_pool_mint.spend "581c${TIME_LOCK_HASH}" 2> /dev/null > tmp
mv tmp plutus.json

STAKE_NFT_POLICY=$(aiken blueprint policy -v stake_pool_mint.mint 2> /dev/null)
STAKE_POOL_ADDR=$(aiken blueprint address -v stake_pool_mint.spend 2> /dev/null)

aiken blueprint apply -v stake_proxy.stake_proxy "581c${TIME_LOCK_HASH}" 2> /dev/null > tmp
mv tmp plutus.json
aiken blueprint apply -v stake_proxy.stake_proxy "582c${BATCHER_CERTIFICATE}" 2> /dev/null > tmp
mv tmp plutus.json
STAKE_PROXY_HASH=$(cat plutus.json | jq --raw-output '.validators[] | select(.title == "stake_proxy.stake_proxy") | .hash')
STAKE_PROXY_ADDR=$(aiken blueprint address -v stake_proxy.stake_proxy 2> /dev/null)

echo -e "Time Lock Hash         = \e[32m ${TIME_LOCK_HASH} \e[0m"
echo -e "Time Lock Address      = \e[32m ${TIME_LOCK_ADDR} \e[0m"
echo -e "Stake NFT Policy       = \e[32m ${STAKE_NFT_POLICY} \e[0m"
echo -e "Stake Pool Address     = \e[32m ${STAKE_POOL_ADDR} \e[0m"
echo -e "Stake Proxy Hash       = \e[32m ${STAKE_PROXY_HASH} \e[0m"
echo -e "Stake Proxy Address    = \e[32m ${STAKE_PROXY_ADDR} \e[0m"

echo
echo