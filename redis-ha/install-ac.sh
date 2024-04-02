#!/usr/bin/env bash

# NOT USED IN REPO AT THIS TIME
# Putting Redis operator pod in hostNetwork: true mode crashes due to other ports exposed at 8080 and 443 that clash with the host ports. 
# The AC isn't necessary here to demonstrate the Redis federated services scenario and cluster-mesh. To be explored later.
# Reference: https://docs.tigera.io/calico/latest/getting-started/kubernetes/managed-public-cloud/eks#:~:text=%3F-,NOTE,-Calico%20networking%20cannot

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/redis-functions.sh

# Make sure kubectl is installed
if ! [ -x "$(command -v kubectl)" ]; then
  echo 'Error: kubectl is required and was not found' >&2
  exit 1
fi

# install_redis_ac