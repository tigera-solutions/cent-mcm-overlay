#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/redis-functions.sh

# Make sure kubectl is installed
if ! [ -x "$(command -v kubectl)" ]; then
  echo 'Error: kubectl is required and was not found' >&2
  exit 1
fi

# install_rec_operator
# echo "Sleeping 3 seconds for CRDs to be created"
# sleep 3
# install_rec_deployment
# create_rerc_configs
# apply_rerc_configs
# create_reaadb_configs
# apply_reaadb_configs
# echo "Sleeping 5 seconds for REAADB status to get updated"
# sleep 5
check_redis_status