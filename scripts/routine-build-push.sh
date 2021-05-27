#! /bin/sh
set -ex

(cd hs && make build push) &
HS=$!
(cd js && make build push) &
JS=$!
(cd scripts/algorand-devnet && make build push) &
ALGO=$!
(cd scripts/ethereum-devnet && make build push) &
ETH=$!
(cd scripts/devnet-cfx && make build push) &
CFX=$!

wait $HS $JS $ALGO $ETH $CFX

set +x
echo "============================"
echo "Don't forget js-reach-stdlib"
echo "============================"
