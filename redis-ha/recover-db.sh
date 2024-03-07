# User vars that can be changed
REDIS_NAMESPACE=redis
TARGET_K8S_CONTEXTS=("kartik+tigera-solutions@tigera.io@cc-eks-mcm1.ca-central-1.eksctl.io")

# Don't touch this (unless you know what you are doing)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

for i in "${!TARGET_K8S_CONTEXTS[@]}"
do
    echo
    echo "Changing context to K8s cluster ${TARGET_K8S_CONTEXTS[i]}"
    kubectl config use-context ${TARGET_K8S_CONTEXTS[i]}
    echo
    TARGET_REC=$(kubectl get rec -n redis -ojsonpath='{.items..metadata.name}')
    echo "Exec into $TARGET_REC-0 pod in $REDIS_NAMESPACE namespace and checking database list to be recovered:"
    kubectl exec -it $TARGET_REC-0 -n $REDIS_NAMESPACE -c redis-enterprise-node -- bash -c 'rladmin recover list'
    echo
    echo "Exec into $TARGET_REC-0 pod in $REDIS_NAMESPACE namespace and recover database:"
    kubectl exec -it $TARGET_REC-0 -n $REDIS_NAMESPACE -c redis-enterprise-node -- bash -c 'rladmin recover all'
    echo
    echo "Exec into $TARGET_REC-0 pod in $REDIS_NAMESPACE namespace and check shards are all showing STATUS:OK"
    kubectl exec -it $TARGET_REC-0 -n $REDIS_NAMESPACE -c redis-enterprise-node -- bash -c 'rladmin status shards'
    echo
    echo "Check that the local database svc endpoints are populated once again:"
    kubectl get endpoints -n $REDIS_NAMESPACE
done