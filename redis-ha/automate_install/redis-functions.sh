#!/usr/bin/env bash

# Source all env variables
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/setup.env

install_rec_operator () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "Create redis namespace and deploying the operator pod and CRDs"
        kubectl create namespace $INSTALL_NAMESPACE
        VERSION=`curl --silent https://api.github.com/repos/RedisLabs/redis-enterprise-k8s-docs/releases/latest | grep tag_name | awk -F'"' '{print $4}'`
        kubectl -n $INSTALL_NAMESPACE apply -f https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/$VERSION/bundle.yaml
        echo "Sleeping 3 seconds for CRDs to be created"
        sleep 3
        echo
    done
}

# This function and accompanying manifests are here for future use.  
# At this moment the only way to get any Admission Controllers working on EKS with Calico CNI is putting them in host-networked mode. 
# Putting Redis operator pod in hostNetwork: true mode crashes due to other ports exposed at 8080 and 443 that clash with the host ports. 
# The AC isn't necessary here to demonstrate the Redis federated services scenario and cluster-mesh. To be explored later.
# Reference: https://docs.tigera.io/calico/latest/getting-started/kubernetes/managed-public-cloud/eks#:~:text=%3F-,NOTE,-Calico%20networking%20cannot
install_redis_ac () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        CERT=`kubectl -n $INSTALL_NAMESPACE get secret admission-tls -o jsonpath='{.data.cert}'`
        sed "s/NAMESPACE_OF_SERVICE_ACCOUNT/$INSTALL_NAMESPACE/g" $SCRIPT_DIR/webhook/webhook.yaml | kubectl create -f -
        cat > $SCRIPT_DIR/webhook/modified-webhook.yaml <<EOF
webhooks:
- name: redisenterprise.admission.redislabs
  clientConfig:
    caBundle: $CERT
    service:
      name: admission
      namespace: $INSTALL_NAMESPACE
      path: /admission
      port: 443
  admissionReviewVersions: ["v1beta1"]
  sideEffects: None
EOF
        kubectl patch ValidatingWebhookConfiguration redis-enterprise-admission --patch "$(cat $SCRIPT_DIR/webhook/modified-webhook.yaml)"
        kubectl label namespace $INSTALL_NAMESPACE $AC_LABEL_KEY=$AC_LABEL_VALUE
        cat > $SCRIPT_DIR/webhook/modified-webhook.yaml <<EOF
webhooks:
- name: redisenterprise.admission.redislabs
  namespaceSelector:
    matchLabels:
      $AC_LABEL_KEY: $AC_LABEL_VALUE
EOF
        kubectl patch ValidatingWebhookConfiguration redis-enterprise-admission --patch "$(cat $SCRIPT_DIR/webhook/modified-webhook.yaml)"
        echo "Testing the AC by passing in an illegal config:"
        kubectl create -f - << EOF
apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseDatabase
metadata:
  name: redis-enterprise-database
  namespace: $INSTALL_NAMESPACE
spec:
  evictionPolicy: illegal
EOF
        echo
    done
}

# 1 CPU and 4 GB is minimum recommended for testing from Redis for REC
install_rec_deployment () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "Installing REC (Redis Enterprise Cluster) in namespace $INSTALL_NAMESPACE:"
        kubectl create -f - << EOF
apiVersion: "app.redislabs.com/v1"
kind: "RedisEnterpriseCluster"
metadata:
  name: ${REC_NAMES[i]}
  namespace: $INSTALL_NAMESPACE
spec:
  extraLabels:
      redis-enterprise-api-region: ${REGION[i]}
  nodes: $REC_POD_REPLICA_COUNT
  redisEnterpriseNodeResources:
    limits:
      memory: 4Gi
    requests:
      cpu: 1
      memory: 4Gi
EOF
        echo      
    done
}

create_rerc_configs () {
    echo "Creating secrets for all participating RECs"
    echo "Making _output directory"
    mkdir -p $SCRIPT_DIR/_output
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "Creating secret manifest for REC named ${REC_NAMES[i]} for region ${REGION[i]} and namespace $INSTALL_NAMESPACE"
        REC_USERNAME=`kubectl -n $INSTALL_NAMESPACE get secret ${REC_NAMES[i]} -o jsonpath='{.data.username}'`
        REC_PASSWORD=`kubectl -n $INSTALL_NAMESPACE get secret ${REC_NAMES[i]} -o jsonpath='{.data.password}'`
        cat > $SCRIPT_DIR/_output/${REC_NAMES[i]}-secret.yaml << EOF
apiVersion: v1
data:
  password: $REC_PASSWORD
  username: $REC_USERNAME
kind: Secret
metadata:
  name: ${REC_NAMES[i]}-secret
  namespace: $INSTALL_NAMESPACE
type: Opaque
EOF
        echo
        echo "Creating RERC manifest for REC named ${RERC_NAMES[i]} using the secret named ${RERC_NAMES[i]}-secret"
        cat > $SCRIPT_DIR/_output/${RERC_NAMES[i]}.yaml << EOF
apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseRemoteCluster
metadata:
  name: ${RERC_NAMES[i]}
  namespace: $INSTALL_NAMESPACE
spec:
  recName: ${REC_NAMES[i]}
  recNamespace: $INSTALL_NAMESPACE
  apiFqdnUrl: ${RERC_NAMES[i]}.$INSTALL_NAMESPACE
  dbFqdnSuffix: -db-${REGION[i]}.$INSTALL_NAMESPACE
  secretName: ${REC_NAMES[i]}-secret
EOF
        echo
    done
}