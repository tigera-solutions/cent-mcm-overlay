#!/usr/bin/env bash

# Source env vars
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/setup.env

apply_rbac () {
  for i in "${!K8S_CONTEXTS[@]}"
  do
    echo "Changing context to K8s cluster ${K8S_CONTEXTS[i]}"
    kubectl config use-context ${K8S_CONTEXTS[i]}
    # Create RBAC and remote service accounts in each site
    echo "Creating remote RBAC and federation SA"
    kubectl apply -f $SCRIPT_DIR/manifests/federation-rem-rbac-kdd.yaml
    kubectl apply -f $SCRIPT_DIR/manifests/federation-remote-sa.yaml
    KUBE_VERSION=$( kubectl version --short 2>&1 | grep Server | cut -d':' -f2 | sed 's/ //g' | sed 's/^.//' )
    RESULT=$(awk -v a="$KUBE_VERSION" -v b=1.24.0 'BEGIN{print(a>=b)}')
    if [[ "$RESULT" -eq 1 ]]; then
      echo "Your K8s version is $KUBE_VERSION which is >1.24.0 so we install SA secret manually"
      kubectl apply -f $SCRIPT_DIR/manifests/federation-remote-secret.yaml
      echo
    else
      echo "Your K8s version is $KUBE_VERSION which is <1.24.0 so we don't need to install SA secret manually"
      echo
    fi
  done
}

generate_kubeconfigs () {
  for i in "${!K8S_CONTEXTS[@]}"
  do
    # Create remote kubeconfig files for the sites
    echo "Making _output directory"
    mkdir -p $SCRIPT_DIR/manifests/_output
    echo "Changing context to K8s cluster ${K8S_CONTEXTS[i]}"
    kubectl config use-context ${K8S_CONTEXTS[i]}
    echo "Create remote cluster kubeconfig for ${REGIONS[i]}"
    cat > $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig <<'EOF'
apiVersion: v1
kind: Config
users:
- name: tigera-federation-remote-cluster
  user:
    token: YOUR_SERVICE_ACCOUNT_TOKEN
clusters:
- name: tigera-federation-remote-cluster
  cluster:
    certificate-authority-data: YOUR_CERTIFICATE_AUTHORITY_DATA
    server: YOUR_SERVER_ADDRESS
contexts:
- name: tigera-federation-remote-cluster-ctx
  context:
    cluster: tigera-federation-remote-cluster
    user: tigera-federation-remote-cluster
current-context: tigera-federation-remote-cluster-ctx
EOF
    KUBE_VERSION=$( kubectl version --short 2>&1 | grep Server | cut -d':' -f2 | sed 's/ //g' | sed 's/^.//' )
    RESULT=$(awk -v a="$KUBE_VERSION" -v b=1.24.0 'BEGIN{print(a>=b)}')
    if [[ "$RESULT" -eq 1 ]]; then
      YOUR_SERVICE_ACCOUNT_TOKEN=$(kubectl get secret tigera-federation-remote-cluster -n kube-system -o go-template='{{.data.token|base64decode}}')
    else
      YOUR_SERVICE_ACCOUNT_TOKEN=$(kubectl get secret -n kube-system $(kubectl get sa -n kube-system tigera-federation-remote-cluster -o jsonpath='{range .secrets[*]}{.name}{"\n"}{end}' | grep token) -o go-template='{{.data.token|base64decode}}')
    fi
    YOUR_CERTIFICATE_AUTHORITY_DATA=$(kubectl config view --flatten --minify -o jsonpath='{range .clusters[*]}{.cluster.certificate-authority-data}{"\n"}{end}')
    YOUR_SERVER_ADDRESS=$(kubectl config view --flatten --minify -o jsonpath='{range .clusters[*]}{.cluster.server}{"\n"}{end}')
    IS_GNU_SED=$(which sed | grep gnu | wc -l)
    if [[ $OSTYPE == linux* ]]; then
      sed -i s,YOUR_SERVICE_ACCOUNT_TOKEN,$YOUR_SERVICE_ACCOUNT_TOKEN,g $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig
      sed -i s,YOUR_CERTIFICATE_AUTHORITY_DATA,$YOUR_CERTIFICATE_AUTHORITY_DATA,g $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig
      sed -i s,YOUR_SERVER_ADDRESS,$YOUR_SERVER_ADDRESS,g $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig
    elif [[ $OSTYPE == darwin* && $IS_GNU_SED -eq 1 ]]; then
      sed -i s,YOUR_SERVICE_ACCOUNT_TOKEN,$YOUR_SERVICE_ACCOUNT_TOKEN,g $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig
      sed -i s,YOUR_CERTIFICATE_AUTHORITY_DATA,$YOUR_CERTIFICATE_AUTHORITY_DATA,g $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig
      sed -i s,YOUR_SERVER_ADDRESS,$YOUR_SERVER_ADDRESS,g $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig
    elif [[ $OSTYPE == darwin* && $IS_GNU_SED -eq 0 ]]; then
      sed -i "" s,YOUR_SERVICE_ACCOUNT_TOKEN,$YOUR_SERVICE_ACCOUNT_TOKEN,g $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig
      sed -i "" s,YOUR_CERTIFICATE_AUTHORITY_DATA,$YOUR_CERTIFICATE_AUTHORITY_DATA,g $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig
      sed -i "" s,YOUR_SERVER_ADDRESS,$YOUR_SERVER_ADDRESS,g $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig
    else
      echo "sed won't work because it seems like you're on Windows or an unsupported OS"
    fi
    echo "Test cluster kubeconfig for ${REGIONS[i]}"
    echo "Both kubectl get nodes and kubectl get svcs should output the necessary list of nodes and svcs"
    echo "Output of kubectl get nodes:"
    kubectl --kubeconfig $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig get nodes
    echo "Output of kubectl get services:"
    kubectl --kubeconfig $SCRIPT_DIR/manifests/_output/calico-demo-${REGIONS[i]}-kubeconfig get services
    echo
  done
}


# Create secrets for other clusters
create_secrets () {
  len=${#REGIONS[@]}
  for i in "${!REGIONS[@]}"
  do
      echo "For kubecontext ${K8S_CONTEXTS[i]} in region ${REGIONS[i]}"
      kubectl config use-context ${K8S_CONTEXTS[i]}
      for (( j=0; j<$len; j++))
      do
      n=$((j+1))
      if [[ $(( n % len )) -ne 0 ]]; then
          NEW_REGION=${REGIONS[(i+j+1) % $len]}
          KUBECONFIG_FILENAME=calico-demo-$NEW_REGION-kubeconfig
          SECRET_NAME=remote-cluster-secret-cluster-$NEW_REGION
          echo "Creating secret named $SECRET_NAME for kubeconfig filename $KUBECONFIG_FILENAME"
          kubectl create secret generic $SECRET_NAME -n calico-system \
              --save-config \
              --dry-run=client \
              --from-literal=datastoreType=kubernetes \
              --from-file=kubeconfig=$SCRIPT_DIR/manifests/_output/calico-demo-$NEW_REGION-kubeconfig \
              -o yaml | \
              kubectl apply -f -
      fi
      done
      echo
  done
}

create_remote_configs () {
# Create remote cluster configs for vxlan overlay clustermesh
  for i in "${!REGIONS[@]}"
  do
  SECRET_NAME=remote-cluster-secret-cluster-${REGIONS[i]}
  cat > $SCRIPT_DIR/manifests/_output/remote-cluster-configuration-${REGIONS[i]}.yaml <<EOF
apiVersion: projectcalico.org/v3
kind: RemoteClusterConfiguration
metadata:
  name: calico-demo-remote-${REGIONS[i]}
spec:
  clusterAccessSecret:
    name: $SECRET_NAME
    namespace: calico-system
    kind: Secret
  syncOptions:
    overlayRoutingMode: Enabled
EOF
  done
}

apply_remote_configs () {
  # Apply relevant remote cluster configs
  len=${#REGIONS[@]}
  for i in "${!REGIONS[@]}"
  do
      echo "For kubecontext ${K8S_CONTEXTS[i]} in region ${REGIONS[i]}"
      kubectl config use-context ${K8S_CONTEXTS[i]}
      # Apply the RBAC file
      echo "Applying the remote cluster RBAC configuration"
      kubectl apply -f $SCRIPT_DIR/manifests/remote-cluster-configuration-rbac.yaml
      for (( j=0; j<$len; j++))
      do
      n=$((j+1))
      if [[ $(( n % len )) -ne 0 ]]; then
          NEW_REGION=${REGIONS[(i+j+1) % $len]}
          REMOTE_CONFIG=remote-cluster-configuration-$NEW_REGION
          echo "Applying remote cluster config named $REMOTE_CONFIG.yaml to cluster ${K8S_CONTEXTS[i]}"
          kubectl apply -f $SCRIPT_DIR/manifests/_output/$REMOTE_CONFIG.yaml
      fi
      done
      echo
  done
}

delete_remote_configs () {
  len=${#REGIONS[@]}
  for i in "${!REGIONS[@]}"
  do
      echo "For kubecontext ${K8S_CONTEXTS[i]} in region ${REGIONS[i]}"
      kubectl config use-context ${K8S_CONTEXTS[i]}
      for (( j=0; j<$len; j++))
      do
      n=$((j+1))
      if [[ $(( n % len )) -ne 0 ]]; then
          NEW_REGION=${REGIONS[(i+j+1) % $len]}
          REMOTE_CONFIG=remote-cluster-configuration-$NEW_REGION
          echo "Deleting remote cluster config named $REMOTE_CONFIG.yaml from cluster ${K8S_CONTEXTS[i]}"
          kubectl delete -f $SCRIPT_DIR/manifests/_output/$REMOTE_CONFIG.yaml
      fi
      done
      # Delete the RBAC file
      echo "Deleting the remote cluster RBAC configuration"
      kubectl delete -f $SCRIPT_DIR/manifests/remote-cluster-configuration-rbac.yaml
      echo
  done
}

delete_secrets () {
  len=${#REGIONS[@]}
  for i in "${!REGIONS[@]}"
  do
      echo "For kubecontext ${K8S_CONTEXTS[i]} in region ${REGIONS[i]}"
      kubectl config use-context ${K8S_CONTEXTS[i]}
      for (( j=0; j<$len; j++))
      do
      n=$((j+1))
      if [[ $(( n % len )) -ne 0 ]]; then
          NEW_REGION=${REGIONS[(i+j+1) % $len]}
          KUBECONFIG_FILENAME=calico-demo-$NEW_REGION-kubeconfig
          SECRET_NAME=remote-cluster-secret-cluster-$NEW_REGION
          echo "Deleting secret named $SECRET_NAME for kubeconfig filename $KUBECONFIG_FILENAME"
          kubectl delete secret $SECRET_NAME -n calico-system
      fi
      done
      echo
  done
}

delete_rbac () {
  for i in "${!K8S_CONTEXTS[@]}"
  do
    echo "Changing context to K8s cluster ${K8S_CONTEXTS[i]}"
    kubectl config use-context ${K8S_CONTEXTS[i]}
    # Delete RBAC and remote service accounts in each site
    echo "Deleting remote RBAC and federation SA"
    KUBE_VERSION=$( kubectl version --short 2>&1 | grep Server | cut -d':' -f2 | sed 's/ //g' | sed 's/^.//' )
    RESULT=$(awk -v a="$KUBE_VERSION" -v b=1.24.0 'BEGIN{print(a>=b)}')
    if [[ "$RESULT" -eq 1 ]]; then
      echo "Your K8s version is $KUBE_VERSION which is >1.24.0 so we delete SA secret manually"
      kubectl delete -f $SCRIPT_DIR/manifests/federation-remote-secret.yaml
    fi
    kubectl delete -f $SCRIPT_DIR/manifests/federation-rem-rbac-kdd.yaml
    kubectl delete -f $SCRIPT_DIR/manifests/federation-remote-sa.yaml
  done
}