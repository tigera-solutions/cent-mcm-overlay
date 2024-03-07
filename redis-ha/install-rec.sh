#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/setup.env
VERSION=`curl --silent https://api.github.com/repos/RedisLabs/redis-enterprise-k8s-docs/releases/latest | grep tag_name | awk -F'"' '{print $4}'`

for i in "${!K8S_CONTEXTS[@]}"
do
    echo "Changing context to K8s cluster ${K8S_CONTEXTS[i]}"
    kubectl config use-context ${K8S_CONTEXTS[i]}
    echo "Create redis namespace and deploying the operator pod and CRDs"
    kubectl create namespace $NAMESPACE
    kubectl -n $NAMESPACE apply -f https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/$VERSION/bundle.yaml
    echo "Sleeping 5 seconds so CRDs get created properly before we install the db pods"
    sleep 5
    kubectl -n $NAMESPACE apply -f $SCRIPT_DIR/${INSTALL_FILES[i]}       
    echo "Check resources are being created"
    kubectl get rec -n $NAMESPACE
    kubectl get all -n $NAMESPACE 
done