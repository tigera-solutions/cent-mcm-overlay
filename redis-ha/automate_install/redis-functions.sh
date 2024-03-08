#!/usr/bin/env bash

# Source all env variables
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/setup.env

# Install the latest REC (Redis Enterprise Cluster) operator and accompanying CRDs
install_rec_operator () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "Create redis namespace and deploying the operator pod and CRDs"
        kubectl create namespace $INSTALL_NAMESPACE
        VERSION=$(curl --silent https://api.github.com/repos/RedisLabs/redis-enterprise-k8s-docs/releases/latest | grep tag_name | awk -F'"' '{print $4}')
        kubectl -n $INSTALL_NAMESPACE apply -f https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/$VERSION/bundle.yaml
        echo
    done
}

# Install the REC (Redis Enterprise Cluster) Deployment in each cluster
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
  uiServiceType: LoadBalancer
  redisEnterpriseNodeResources:
    limits:
      memory: 4Gi
    requests:
      cpu: 1
      memory: 4Gi
EOF
        echo "Checking REC status"
        kubectl get rec -n $INSTALL_NAMESPACE
        echo      
    done
}

# Create RERC (Redis Enterprise Remote Cluster) CR and accompanying manifest files
create_rerc_configs () {
    echo "Creating secrets for all participating RECs"
    echo "Making _output directory"
    mkdir -p $SCRIPT_DIR/_output
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "Creating secret manifest for REC named ${REC_NAMES[i]} for region ${REGION[i]} and namespace $INSTALL_NAMESPACE"
        REC_USERNAME=$(kubectl -n $INSTALL_NAMESPACE get secret ${REC_NAMES[i]} -o jsonpath='{.data.username}')
        REC_PASSWORD=$(kubectl -n $INSTALL_NAMESPACE get secret ${REC_NAMES[i]} -o jsonpath='{.data.password}')
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
        echo "Creating RERC manifest for ${REGION[i]} using the secret named ${REC_NAMES[i]}-secret"
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
        echo "Creating RERC API endpoint federated services manifest"
        cat > $SCRIPT_DIR/_output/${RERC_NAMES[i]}-fedsvc.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${RERC_NAMES[i]}
  namespace: $INSTALL_NAMESPACE
  annotations:
    federation.tigera.io/serviceSelector: redis-enterprise-api-region == "${REGION[i]}"
spec:
  ports:
  - name: sentinel
    port: 8001
    protocol: TCP
    targetPort: 8001
  - name: api
    port: 443
    protocol: TCP
    targetPort: 9443
  type: ClusterIP
EOF
        echo
    done
}

apply_rerc_configs () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        for j in "${!INSTALL_K8S_CONTEXTS[@]}"
        do
            echo "Applying the secret manifest ${REC_NAMES[j]}-secret"
            kubectl create -f $SCRIPT_DIR/_output/${REC_NAMES[j]}-secret.yaml
            echo
            echo "Applying the RERC manifest ${RERC_NAMES[j]}"
            kubectl create -f $SCRIPT_DIR/_output/${RERC_NAMES[j]}.yaml
            echo
            echo "Applying RERC API endpoint federated services manifest for ${RERC_NAMES[i]} "
            kubectl create -f $SCRIPT_DIR/_output/${RERC_NAMES[i]}-fedsvc.yaml
        done
        echo "Checking RERC status"
        kubectl get rerc -n $INSTALL_NAMESPACE
        echo
    done
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "Check the federated API endpoints got populated"
        echo "Running: kubectl get endpoints -n $INSTALL_NAMESPACE"
        kubectl get endpoints -n $INSTALL_NAMESPACE
        echo
    done
}

# Create REAADB (Redis Enterprise Active-Active Database) and accompanying manifests
# The main REAADB CR manifest only needs to be applied once on one cluster
create_reaadb_configs () {
    echo "Create the READDB blank secret manifest to create a database without authentication"
    cat > $SCRIPT_DIR/_output/$REAADB_NAME-secret.yaml << EOF
apiVersion: v1
data:
  password: ""
kind: Secret
metadata:
  name: $REAADB_NAME-secret
  namespace: redis
type: Opaque
EOF
    echo "Create the REAADB CR manifest"
    cat > $SCRIPT_DIR/_output/$REAADB_NAME.yaml << EOF
apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseActiveActiveDatabase
metadata:
  name: $REAADB_NAME
  namespace: $INSTALL_NAMESPACE
  labels:
    app: redis-enterprise
spec:
  globalConfigurations:
    databaseSecretName: $REAADB_NAME-secret
    databasePort: $REAADB_PORT
    memorySize: 200MB
    shardCount: 3
  participatingClusters:  
EOF
    for i in "${!RERC_NAMES[@]}"
    do
        cat >> $SCRIPT_DIR/_output/$REAADB_NAME.yaml << EOF
      - name: ${RERC_NAMES[i]}
EOF
    done
    echo "Create the REAADB replication endpoint federated services manifests"
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        cat > $SCRIPT_DIR/_output/$REAADB_NAME-${REGION[i]}-replication-fedsvc.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: $REAADB_NAME-db-${REGION[i]}.$INSTALL_NAMESPACE
  namespace: $INSTALL_NAMESPACE
  annotations:
    federation.tigera.io/serviceSelector: redis-enterprise-dbreplication-region == "${REGION[i]}"
spec:
  ports:
  - name: redis
    port: 443
    protocol: TCP
    targetPort: $REAADB_PORT
  type: ClusterIP
EOF
    done
}

apply_reaadb_configs () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "Applying the $REAADB_NAME-secret manifest"
        kubectl create -f $SCRIPT_DIR/_output/$REAADB_NAME-secret.yaml
        for j in "${!INSTALL_K8S_CONTEXTS[@]}"
        do
            echo "Applying the REAADB replication endpoint federated services manifest $REAADB_NAME-${REGION[j]}-replication-fedsvc.yaml"
            kubectl create -f $SCRIPT_DIR/_output/$REAADB_NAME-${REGION[j]}-replication-fedsvc.yaml
        done
        echo
    done
    echo
    echo "Changing context back to K8s cluster ${INSTALL_K8S_CONTEXTS[0]}"
    kubectl config use-context ${INSTALL_K8S_CONTEXTS[0]}
    echo "Finally applying the REAADB CR manifest"
    kubectl create -f $SCRIPT_DIR/_output/$REAADB_NAME.yaml
    echo "If any errors show up, check configs"
    echo
    echo "Patch the $REAADB_NAME service with the correct label to enable federation"
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "Running: kubectl label svc -n $INSTALL_NAMESPACE $REAADB_NAME redis-enterprise-dbreplication-region=${REGION[i]}"
        kubectl label svc -n $INSTALL_NAMESPACE $REAADB_NAME redis-enterprise-dbreplication-region=${REGION[i]}
        echo
    done
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "Check the DB replication federated endpoints got populated"
        echo "Running: kubectl get endpoints -n $INSTALL_NAMESPACE | grep $REAADB_NAME-db"
        kubectl get endpoints -n $INSTALL_NAMESPACE | grep $REAADB_NAME-db
        echo "Check the REAADB config and replication status"
        echo "Running: kubectl get reaadb -n $INSTALL_NAMESPACE"
        kubectl get reaadb -n $INSTALL_NAMESPACE
        echo
    done    
    echo
}

check_redis_status () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo
        echo "Checking all the Redis CRs"
        echo "Running: kubectl get rec -n $INSTALL_NAMESPACE"
        kubectl get rec -n $INSTALL_NAMESPACE
        echo
        echo "Running: kubectl get rerc -n $INSTALL_NAMESPACE"
        kubectl get rerc -n $INSTALL_NAMESPACE
        echo
        echo "Running: kubectl get reaadb -n INSTALL_NAMESPACE"
        kubectl get reaadb -n $INSTALL_NAMESPACE
        echo
        TARGET_REC=$(kubectl get rec -n $INSTALL_NAMESPACE -ojsonpath='{.items..metadata.name}')
        echo "Exec into $TARGET_REC-0 pod in $REDIS_NAMESPACE namespace and checking the status of the database"
        kubectl exec -it $TARGET_REC-0 -n $INSTALL_NAMESPACE -c redis-enterprise-node -- bash -c 'rladmin status'
        echo
        echo "Check all Redis svcs in $INSTALL_NAMESPACE namespace with their labels"
        kubectl get svc -n $INSTALL_NAMESPACE --show-labels
        echo
        echo "Check all Redis endpoints in $INSTALL_NAMESPACE namespace"
        kubectl get endpoints -n $INSTALL_NAMESPACE
        echo
        echo
    done
}

# NOT USED IN REPO AT THIS TIME
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
        CERT=$(kubectl -n $INSTALL_NAMESPACE get secret admission-tls -o jsonpath='{.data.cert}')
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