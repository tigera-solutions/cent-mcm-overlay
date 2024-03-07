# User vars that can be changed
REDIS_NAMESPACE=redis
TARGET_K8S_CONTEXTS=("kartik+tigera-solutions@tigera.io@cc-eks-mcm1.ca-central-1.eksctl.io")

# Don't touch this (unless you know what you are doing)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

for i in "${!TARGET_K8S_CONTEXTS[@]}"
do
    echo "Changing context to K8s cluster ${TARGET_K8S_CONTEXTS[i]}"
    kubectl config use-context ${TARGET_K8S_CONTEXTS[i]}
    echo
    TARGET_REC=$(kubectl get rec -n redis -ojsonpath='{.items..metadata.name}')
    echo "Putting Redis Enterprise Cluster named $TARGET_REC in namespace $REDIS_NAMESPACE into recovery mode"
    kubectl patch rec $TARGET_REC -n $REDIS_NAMESPACE --type merge --patch '{"spec":{"clusterRecovery":true}}'
    echo "Sleeping for 3 seconds before performing checks"
    sleep 3
    echo       
    echo "Check that the REC deployment is in recovery mode:"
    kubectl get rec -n $REDIS_NAMESPACE
    echo
    echo "Check that the local database svc endpoints are empty to ensure that the database has been taken down:" 
    kubectl get endpoints -n $REDIS_NAMESPACE 
done