#!/usr/bin/env bash

# Define color codes
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
NC=$(tput sgr0) # No Color

# Source all env variables
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/setup.env

# Install the latest REC (Redis Enterprise Cluster) operator and accompanying CRDs
install_rec_operator () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "${YELLOW}Create $INSTALL_NAMESPACE namespace and deploying the redis-operator pod and CRDs${NC}"
        kubectl create namespace $INSTALL_NAMESPACE
        VERSION=$(curl --silent https://api.github.com/repos/RedisLabs/redis-enterprise-k8s-docs/releases/latest | grep tag_name | awk -F'"' '{print $4}')
        kubectl -n $INSTALL_NAMESPACE apply -f https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/$VERSION/bundle.yaml
        echo "Sleeping 3 seconds for CRDs to be properly created"
        sleep 3
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
        echo "${YELLOW}Installing REC (Redis Enterprise Cluster) in namespace $INSTALL_NAMESPACE${NC}"
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
        echo "${GREEN}REC installation applied in namespace $INSTALL_NAMESPACE${NC}"
        echo
        echo "${YELLOW}Checking REC status${NC}"
        START_TIME=$(date +%s)
        MAX_TIME=$((10*60))
        SPEC_STATUS=""
        # Run the loop until SPEC_STATUS is 'Running' or 10 minutes have passed
        until [ "$SPEC_STATUS" = "Running" ] || [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; do
            echo "${YELLOW}Checking status of Redis pods${NC}"
            echo "${CYAN}Running: kubectl get pods -n $INSTALL_NAMESPACE${NC}"
            kubectl get pods -n $INSTALL_NAMESPACE
            # Update SPEC_STATUS
            SPEC_STATUS=$(kubectl get rec -n $INSTALL_NAMESPACE -ojsonpath='{.items..status.state}')
            # Sleeping for 10 seconds before checking again
            echo "${BLUE}The REC status is $SPEC_STATUS, sleeping for 10 seconds and checking again${NC}"
            sleep 10
            echo
        done
        if [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; then
            echo "${RED}Stopped checking REC status because 10 minutes have passed, you need to debug why${NC}"
            echo "${RED}The install script will fully exit here so that you can manually debug further as the rest of the steps cannot proceed${NC}"
            exit 1
        else
            echo "${GREEN}Stopped checking because REC status is 'Running', going to proceed with next steps${NC}"
        fi
        echo "${YELLOW}Listing REC status${NC}"
        kubectl get rec -n $INSTALL_NAMESPACE
        echo      
    done
}

# Create RERC (Redis Enterprise Remote Cluster) CR and accompanying manifest files
create_rerc_configs () {
    echo "${YELLOW}Creating secrets for all participating RECs${NC}"
    echo "${YELLOW}Making _output directory (if it doesn't already exist)${NC}"
    mkdir -p $SCRIPT_DIR/_output
    echo
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "${YELLOW}Creating secret manifest for REC named ${REC_NAMES[i]} for region ${REGION[i]} and namespace $INSTALL_NAMESPACE${NC}"
        REC_USERNAME=$(kubectl -n $INSTALL_NAMESPACE get secret ${REC_NAMES[i]} -o jsonpath='{.data.username}')
        REC_PASSWORD=$(kubectl -n $INSTALL_NAMESPACE get secret ${REC_NAMES[i]} -o jsonpath='{.data.password}')
        cat > $SCRIPT_DIR/_output/redis-enterprise-${RERC_NAMES[i]}-secret.yaml << EOF
apiVersion: v1
data:
  password: $REC_PASSWORD
  username: $REC_USERNAME
kind: Secret
metadata:
  name: redis-enterprise-${RERC_NAMES[i]}
  namespace: $INSTALL_NAMESPACE
type: Opaque
EOF
        echo "${YELLOW}Creating RERC manifest for ${REGION[i]} using the secret named redis-enterprise-${RERC_NAMES[i]}${NC}"
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
  secretName: redis-enterprise-${RERC_NAMES[i]}
EOF
        echo "${YELLOW}Creating RERC API endpoint federated services manifest${NC}"
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
            echo "${YELLOW}Applying the secret manifest ${REC_NAMES[j]}-secret${NC}"
            kubectl create -f $SCRIPT_DIR/_output/redis-enterprise-${RERC_NAMES[j]}-secret.yaml
            echo
            echo "${YELLOW}Applying the RERC manifest ${RERC_NAMES[j]}${NC}"
            kubectl create -f $SCRIPT_DIR/_output/${RERC_NAMES[j]}.yaml
            echo
            echo "${YELLOW}Applying RERC API endpoint federated services manifest for ${RERC_NAMES[j]}${NC}"
            kubectl create -f $SCRIPT_DIR/_output/${RERC_NAMES[j]}-fedsvc.yaml
        done
        echo "${YELLOW}Checking RERC status${NC}"
        kubectl get rerc -n $INSTALL_NAMESPACE
        echo
    done
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "${YELLOW}Check the federated API endpoints got populated${NC}"
        echo "${YELLOW}Running: kubectl get endpoints -n $INSTALL_NAMESPACE${NC}"
        kubectl get endpoints -n $INSTALL_NAMESPACE
        echo
    done
}

# Create REAADB (Redis Enterprise Active-Active Database) and accompanying manifests
create_reaadb_configs () {
    echo "${YELLOW}Creating the READDB blank secret manifest to create a database without authentication${NC}"
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
    echo "${YELLOW}Creating the REAADB CR manifest${NC}"
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
    echo "${YELLOW}Creating the REAADB replication endpoint federated services manifests${NC}"
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        cat > $SCRIPT_DIR/_output/$REAADB_NAME-${REGION[i]}-replication-fedsvc.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: $REAADB_NAME-db-${REGION[i]}
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

# The main REAADB CR manifest only needs to be applied once on one cluster
apply_reaadb_configs () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "${YELLOW}Applying the $REAADB_NAME-secret manifest${NC}"
        kubectl create -f $SCRIPT_DIR/_output/$REAADB_NAME-secret.yaml
        for j in "${!INSTALL_K8S_CONTEXTS[@]}"
        do
            echo "${YELLOW}Applying the REAADB replication endpoint federated services manifest $REAADB_NAME-${REGION[j]}-replication-fedsvc.yaml${NC}"
            kubectl create -f $SCRIPT_DIR/_output/$REAADB_NAME-${REGION[j]}-replication-fedsvc.yaml
        done
        echo
    done
    echo
    echo "${YELLOW}Changing context back to K8s cluster ${INSTALL_K8S_CONTEXTS[0]}${NC}"
    kubectl config use-context ${INSTALL_K8S_CONTEXTS[0]}
    echo "${YELLOW}Finally applying the REAADB CR manifest${NC}"
    kubectl create -f $SCRIPT_DIR/_output/$REAADB_NAME.yaml
    echo "${YELLOW}Checking REAADB status${NC}"
    START_TIME=$(date +%s)
    MAX_TIME=$((10*60))
    REAADB_STATUS=""
    # Run the loop until REAADB_STATUS is 'Running' or 10 minutes have passed
    until [ "$REAADB_STATUS" = "active" ] || [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; do
        echo "${YELLOW}Checking status of the REAADB${NC}"
        # Update REAADB_STATUS
        REAADB_STATUS=$(kubectl get reaadb $REAADB_NAME -n $INSTALL_NAMESPACE -ojsonpath='{..status.status}')
        # Sleeping for 10 seconds before checking again
        echo "${BLUE}The REAADB status is $REAADB_STATUS, sleeping for 10 seconds and checking again${NC}"
        sleep 10
        echo
    done
    if [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; then
        echo "${RED}Stopped checking REAADB status because 10 minutes have passed, you need to debug why${NC}"
        echo "${RED}The install script will fully exit here so that you can manually debug further as the rest of the steps cannot proceed${NC}"
        exit 1
    else
        echo "${GREEN}Stopped checking because REAADB status is 'active', going to proceed with next steps${NC}"
    fi
    START_TIME=$(date +%s)
    MAX_TIME=$((5*60))
    REAADB_SVC_STATUS=""
    until [ "$REAADB_SVC_STATUS" = "$REAADB_NAME" ] || [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; do
        echo "${YELLOW}Checking that the local db service $REAADB_NAME got created in the $INSTALL_NAMESPACE namespace${NC}"
        # Update REAADB_SVC_STATUS
        REAADB_SVC_STATUS=$(kubectl get svc -n $INSTALL_NAMESPACE $REAADB_NAME -ojsonpath='{.metadata.name}')
        # Sleeping for 10 seconds before checking again
        echo "${BLUE}The $REAADB_NAME local service hasn't been created yet, sleeping for 10 seconds and checking again${NC}"
        sleep 10
        echo
    done
    if [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; then
        echo "${RED}Stopped checking REAADB service status because 5 minutes have passed, you need to debug why${NC}"
        echo "${RED}The install script will fully exit here so that you can manually debug further as the rest of the steps cannot proceed${NC}"
        exit 1
    else
        echo "${GREEN}Stopped checking because the $REAADB_NAME local service now exists, going to proceed with next steps${NC}"
    fi
    # echo "${BLUE}Sleeping for 10 seconds for the resources to be created${NC}"
    # sleep 10
    echo
    echo "${YELLOW}Patching the local $REAADB_NAME service with the correct label to enable federation${NC}"
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "${YELLOW}Running: kubectl label svc -n $INSTALL_NAMESPACE $REAADB_NAME redis-enterprise-dbreplication-region=${REGION[i]}${NC}"
        kubectl label svc -n $INSTALL_NAMESPACE $REAADB_NAME redis-enterprise-dbreplication-region=${REGION[i]}
        echo
    done
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "${YELLOW}Checking the DB replication federated endpoints got populated${NC}"
        echo "${YELLOW}Running: kubectl get endpoints -n $INSTALL_NAMESPACE | grep $REAADB_NAME-db${NC}"
        kubectl get endpoints -n $INSTALL_NAMESPACE | grep $REAADB_NAME-db
        echo
    done
    echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[0]}"
    kubectl config use-context ${INSTALL_K8S_CONTEXTS[0]}
    # echo "${BLUE}Sleeping for 10 seconds for replication status to be updated${NC}"
    # sleep 10
    echo
    echo "${YELLOW}Waiting for the REAADB replication status to come up${NC}"
    START_TIME=$(date +%s)
    MAX_TIME=$((10*60))
    REAADB_REP_STATUS=""
    until [ "$REAADB_REP_STATUS" = "up" ] || [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; do
        echo "${YELLOW}Checking the REAADB replication status for $REAADB_NAME${NC}"
        # Update REAADB_REP_STATUS
        REAADB_REP_STATUS=$(kubectl get reaadb $REAADB_NAME -n $INSTALL_NAMESPACE -ojsonpath='{..status.replicationStatus}')
        # Sleeping for 10 seconds before checking again
        echo "${BLUE}The replication status for $REAADB_NAME is $REAADB_REP_STATUS, sleeping for 10 seconds and checking again${NC}"
        sleep 10
        echo
    done
    if [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; then
        echo "${RED}Stopped checking REAADB replication status because 10 minutes have passed, you need to debug why${NC}"
        echo "${RED}The install script will fully exit here so that you can manually debug further as the rest of the steps cannot proceed${NC}"
        exit 1
    else
        echo "${GREEN}Stopped checking because the $REAADB_NAME replication status is now $REAADB_REP_STATUS, going to proceed with next steps${NC}"
    fi
    echo
}

create_db_fedsvc () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo
        echo "${YELLOW}Creating database federated service named $REAADB_NAME-federated in namespace $INSTALL_NAMESPACE${NC}"
        kubectl create -f - << EOF
apiVersion: v1
kind: Service
metadata:
  name: $REAADB_NAME-federated
  namespace: $INSTALL_NAMESPACE
  annotations:
    federation.tigera.io/serviceSelector: federation == "yes"
spec:
  ports:
    - name: redis
      port: $REAADB_PORT
      protocol: TCP
  type: ClusterIP
EOF
        echo "${YELLOW}Labeling the local $REAADB_NAME service to federate it${NC}"
        echo "${YELLOW}Running: kubectl label svc -n $INSTALL_NAMESPACE $REAADB_NAME federation=yes${NC}"
        kubectl label svc -n $INSTALL_NAMESPACE $REAADB_NAME federation=yes
        echo "${YELLOW}Check the endpoints for the $REAADB_NAME-federated service for local and remote endpoints${NC}"
        echo "${YELLOW}Running: kubectl get endpoints -n $INSTALL_NAMESPACE $REAADB_NAME-federated${NC}"
        kubectl get endpoints -n $INSTALL_NAMESPACE $REAADB_NAME-federated
        echo
    done
}

check_redis_status () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo
        echo "${YELLOW}Checking all the Redis CRs${NC}"
        echo "${CYAN}Running: kubectl get rec -n $INSTALL_NAMESPACE${NC}"
        kubectl get rec -n $INSTALL_NAMESPACE
        echo
        echo "${CYAN}Running: kubectl get rerc -n $INSTALL_NAMESPACE${NC}"
        kubectl get rerc -n $INSTALL_NAMESPACE
        echo
        echo "${CYAN}Running: kubectl get reaadb -n INSTALL_NAMESPACE${NC}"
        kubectl get reaadb -n $INSTALL_NAMESPACE
        echo
        TARGET_REC=$(kubectl get rec -n $INSTALL_NAMESPACE -ojsonpath='{.items..metadata.name}')
        echo "${YELLOW}Exec into $TARGET_REC-0 pod in $INSTALL_NAMESPACE namespace and checking the status of the database${NC}"
        kubectl exec -it $TARGET_REC-0 -n $INSTALL_NAMESPACE -c redis-enterprise-node -- bash -c 'rladmin status'
        echo
        echo "${YELLOW}Checking all Redis svcs in $INSTALL_NAMESPACE namespace with their labels${NC}"
        kubectl get svc -n $INSTALL_NAMESPACE --show-labels
        echo
        echo "${YELLOW}Checking all Redis endpoints in $INSTALL_NAMESPACE namespace${NC}"
        kubectl get endpoints -n $INSTALL_NAMESPACE
        echo
        echo
    done
}

# Clean-up functions
delete_db_fedsvc () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "${YELLOW}Deleting database federated service named $REAADB_NAME-federated in namespace $INSTALL_NAMESPACE${NC}"
        kubectl delete svc $REAADB_NAME-federated -n $INSTALL_NAMESPACE
        echo
    done
}

delete_reaadb () {
    echo "Changing context back to K8s cluster ${INSTALL_K8S_CONTEXTS[0]}"
    kubectl config use-context ${INSTALL_K8S_CONTEXTS[0]}
    echo "${YELLOW}Deleting REAADB CR${NC}"
    kubectl delete reaadb $REAADB_NAME -n $INSTALL_NAMESPACE
    echo
    echo "${YELLOW}Deleting REAADB replication federated services${NC}"
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        for j in "${!INSTALL_K8S_CONTEXTS[@]}"
        do
            echo "${YELLOW}Deleting the federated service $REAADB_NAME-db-${REGION[j]}${NC}"
            kubectl delete svc -n $INSTALL_NAMESPACE $REAADB_NAME-db-${REGION[j]}
        done
        echo "${YELLOW}Deleting the REAADB secret $REAADB_NAME-secret${NC}"
        kubectl delete secret -n $INSTALL_NAMESPACE $REAADB_NAME-secret
        echo
        echo "${YELLOW}Checking that the REAADB CR is cleaned up${NC}"
        kubectl get reaadb -n $INSTALL_NAMESPACE
        echo "${YELLOW}Checking that the REAADB federated services are cleaned up${NC}"
        kubectl get svc -n $INSTALL_NAMESPACE | grep $REAADB_NAME-db
        echo "${YELLOW}Checking that the REAADB secrets are cleaned up${NC}"
        kubectl get secret -n $INSTALL_NAMESPACE | grep $REAADB_NAME-secret
        echo
        echo
    done       
}

delete_rerc () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo
        echo "${YELLOW}Deleting the RERC CRs${NC}"
        for j in "${!INSTALL_K8S_CONTEXTS[@]}"
        do
            echo "${YELLOW}Deleting RERC named ${RERC_NAMES[j]} in $INSTALL_NAMESPACE namespace${NC}"
            kubectl delete rerc -n $INSTALL_NAMESPACE ${RERC_NAMES[j]}
        done
        echo
        echo "${YELLOW}Deleting the RERC API endpoint federated services${NC}"
        for j in "${!INSTALL_K8S_CONTEXTS[@]}"
        do
            echo "${YELLOW}Deleting the RERC federated svc ${RERC_NAMES[j]} in $INSTALL_NAMESPACE namespace${NC}"
            kubectl delete svc -n $INSTALL_NAMESPACE ${RERC_NAMES[j]}
        done
        echo
        echo "${YELLOW}Deleting the RERC secrets${NC}"
        for j in "${!INSTALL_K8S_CONTEXTS[@]}"
        do
            echo "${YELLOW}Deleting the RERC secret ${REC_NAMES[j]}-secret in $INSTALL_NAMESPACE namespace${NC}"
            kubectl delete secret -n $INSTALL_NAMESPACE redis-enterprise-${RERC_NAMES[j]}
        done
        echo
        echo "${YELLOW}Checking that RERC objects are cleaned up${NC}"
        kubectl get rerc -n $INSTALL_NAMESPACE
        echo "${YELLOW}Checking that the RERC federated svcs are cleaned up${NC}"
        kubectl get svc -n $INSTALL_NAMESPACE
        echo "${YELLOW}Checking that the RERC secrets are cleaned up${NC}"
        kubectl get secret -n $INSTALL_NAMESPACE
    done
}

delete_rec () {
    for i in "${!INSTALL_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${INSTALL_K8S_CONTEXTS[i]}"
        kubectl config use-context ${INSTALL_K8S_CONTEXTS[i]}
        echo "${YELLOW}Deleting REC objects${NC}"
        kubectl delete rec -n $INSTALL_NAMESPACE ${REC_NAMES[i]}
        echo "${YELLOW}Checking the REC objects are cleaned up${NC}"
        kubectl get rec -n $INSTALL_NAMESPACE
        echo "${YELLOW}Checking the REC svcs are cleaned up${NC}"
        kubectl get svc -n $INSTALL_NAMESPACE
        echo "${YELLOW}Checking the REC secrets are cleaned up${NC}"
        kubectl get secret -n $INSTALL_NAMESPACE
    done
}

# Test case functions
takedown_rec () {
    for i in "${!TARGET_K8S_CONTEXTS[@]}"
    do
        echo "Changing context to K8s cluster ${TARGET_K8S_CONTEXTS[i]}"
        kubectl config use-context ${TARGET_K8S_CONTEXTS[i]}
        echo
        TARGET_REC=$(kubectl get rec -n $INSTALL_NAMESPACE -ojsonpath='{.items..metadata.name}')
        echo "${YELLOW}Putting Redis Enterprise Cluster named $TARGET_REC in namespace $INSTALL_NAMESPACE into recovery mode${NC}"
        kubectl patch rec $TARGET_REC -n $INSTALL_NAMESPACE --type merge --patch '{"spec":{"clusterRecovery":true}}'
        echo "${BLUE}Sleeping for 3 seconds before performing checks${NC}"
        sleep 3
        echo       
        echo "${YELLOW}Check that the REC deployment is in recovery mode${NC}"
        kubectl get rec -n $INSTALL_NAMESPACE
        echo
        echo "${YELLOW}Check that the local database svc endpoints are empty to ensure that the database has been taken down${NC}" 
        kubectl get endpoints $REAADB_NAME -n $INSTALL_NAMESPACE
        echo "${YELLOW}Check that the federated database svc endpoints are properly updated${NC}"
        kubectl get endpoints $REAADB_NAME-federated -n $INSTALL_NAMESPACE
        echo 
    done
}

recover_db () {
    for i in "${!TARGET_K8S_CONTEXTS[@]}"
    do
        echo
        echo "Changing context to K8s cluster ${TARGET_K8S_CONTEXTS[i]}"
        kubectl config use-context ${TARGET_K8S_CONTEXTS[i]}
        echo
        TARGET_REC=$(kubectl get rec -n redis -ojsonpath='{.items..metadata.name}')
        echo "${YELLOW}Checking that the REC has fully recovered the pods:"
        START_TIME=$(date +%s)
        MAX_TIME=$((10*60))
        SPEC_STATUS=""
        # Run the loop until SPEC_STATUS is 'Running' or 10 minutes have passed
        until [ "$SPEC_STATUS" = "Running" ] || [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; do
            echo "${YELLOW}Checking status of Redis pods${NC}"
            echo "${CYAN}Running: kubectl get pods -n $INSTALL_NAMESPACE${NC}"
            kubectl get pods -n $INSTALL_NAMESPACE
            # Update SPEC_STATUS
            SPEC_STATUS=$(kubectl get rec -n $INSTALL_NAMESPACE -ojsonpath='{.items..status.state}')
            # Sleeping for 10 seconds before checking again
            echo "${BLUE}The REC status is $SPEC_STATUS, sleeping for 10 seconds and checking again${NC}"
            sleep 10
            echo
        done
        if [ $(( $(date +%s) - START_TIME )) -ge $MAX_TIME ]; then
            echo "${RED}Stopped checking REC status because 10 minutes have passed, you need to debug why${NC}"
            echo "${RED}The script will fully exit here so that you can manually debug further${NC}"
            exit 1
        else
            echo "${GREEN}Stopped checking because REC status is 'Running' and it is fully recovered, going to proceed with next steps${NC}"
        fi
        echo "${YELLOW}Exec into $TARGET_REC-0 pod in $INSTALL_NAMESPACE namespace and checking database list to be recovered${NC}"
        kubectl exec -it $TARGET_REC-0 -n $INSTALL_NAMESPACE -c redis-enterprise-node -- bash -c 'rladmin recover list'
        echo
        echo "${YELLOW}Exec into $TARGET_REC-0 pod in $INSTALL_NAMESPACE namespace and recover database${NC}"
        kubectl exec -it $TARGET_REC-0 -n $INSTALL_NAMESPACE -c redis-enterprise-node -- bash -c 'rladmin recover all'
        echo
        echo "${BLUE}Sleeping 5 seconds to allow database shards to recover${NC}"
        sleep 5
        echo
        echo "${YELLOW}Exec into $TARGET_REC-0 pod in $INSTALL_NAMESPACE namespace and check shards are all showing${NC} ${GREEN}STATUS:OK${NC}"
        kubectl exec -it $TARGET_REC-0 -n $INSTALL_NAMESPACE -c redis-enterprise-node -- bash -c 'rladmin status shards'
        echo
        echo "${YELLOW}Check that the local database svc endpoints are populated once again${NC}"
        kubectl get endpoints $REAADB_NAME -n $INSTALL_NAMESPACE
        echo "${YELLOW}Check that the federated database svc endpoints are properly updated${NC}"
        kubectl get endpoints $REAADB_NAME-federated -n $INSTALL_NAMESPACE
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