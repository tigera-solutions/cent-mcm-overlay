# EKS Cluster mesh setup in Overlay/VXLAN mode on Calico Enterprise

> :warning: **This repo is purely a work-in-progress(WIP) and is in active development. Other than contributors, anyone else should probably not try the stuff in this repo and expect it to work as is until it's finished and ready!**

We will be using the Calico Enterprise early preview version v3.18.0-2.0 as per the docs [here](https://docs.tigera.io/calico-enterprise/3.18/getting-started/install-on-clusters/eks#install-eks-with-calico-networking)

## Notes

- There will need to be two EKS clusters running Calico CNI, this is done in different regions with VPC peering to peer the node CIDRs.
- VPC CIDRs for each cluster will need to be unique to allow peering to happen, and pod cidrs and svc cidrs also need to be unique for each cluster. This is set in the eksctl config file and the Calico custom resources config file respectively.
- [Next doc for clustermesh](https://docs.tigera.io/calico-enterprise/3.18/multicluster/federation/kubeconfig)

## Steps

Following steps are done for a 2-cluster setup using eksctl from a config file

### Cluster-1 setup with ```eksctl```

[Reference](https://docs.tigera.io/calico-enterprise/next/getting-started/install-on-clusters/eks#install-eks-with-calico-networking)

- Change the values under ```manifests/eksctl-config-cluster1.yaml``` as needed. Note the VPC and svc cidrs.

- Create the cluster:

  ```bash
  eksctl create cluster -f manifests/eksctl-config-cluster1.yaml
  ```

- Once the cluster is up and you have ```kubectl``` access, delete the ```aws-node``` daemonset:
  
  ```bash
  kubectl delete daemonset -n kube-system aws-node
  ```

- Next, decide if you want to install Calico Enterprise mgmt. plane on this cluster or if you want to connect the cluster to Calico Cloud.

### Calico Enterprise Installation Steps

> :warning: **Ignore this section if going the Calico Cloud route, refer to the next section for those steps**

- Apply the operator and prometheus manifests from the repo:

  ```bash
  kubectl create -f https://downloads.tigera.io/ee/v3.18.0-2.0/manifests/tigera-operator.yaml
  ```

  ```bash
  kubectl create -f https://downloads.tigera.io/ee/v3.18.0-2.0/manifests/tigera-prometheus-operator.yaml
  ```

- Get a pull secret: The official build uses the quay.io images, so you'll need a pull secret. [This doc](https://tigera.atlassian.net/wiki/spaces/CS/pages/623575278/Creating+Pull+secrets+and+License+files+for+PoC+s) has options on how to generate one as per the official POC/testing process.

> :warning: **Please make sure to delete pull secrets after testing or if not being used by an active/paying customer or an active POC**

- Install the pull secret:
  
  ```bash
  kubectl create secret generic tigera-pull-secret --type=kubernetes.io/dockerconfigjson -n tigera-operator --from-file=.dockerconfigjson=<path/to/pull/secret>
  ```

- For the Prometheus operator, create the pull secret in the tigera-prometheus namespace and then patch the deployment

  ```bash
  kubectl create secret generic tigera-pull-secret --type=kubernetes.io/dockerconfigjson -n tigera-prometheus --from-file=.dockerconfigjson=<path/to/pull/secret>
  ```

  ```bash
  kubectl patch deployment -n tigera-prometheus calico-prometheus-operator -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name": "tigera-pull-secret"}]}}}}'
  ```

- Modify the ```mgmtcluster-custom-resources-example.yaml``` file as needed and apply it.
  
  ```bash
  kubectl create -f manifests/mgmtcluster-custom-resources-example.yaml
  ```

- For ```LogStorage``` , install the EBS CSI driver: [EBS on EKS docs reference](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)

  One quick way of doing this is with using your AWS access key id and secret access key to create the ```Secret``` object for the EBS CSI controller:
  
  Export the vars:

  ```bash
  export AWS_ACCESS_KEY_ID=<my-access-key-id>
  export AWS_SECRET_ACCESS_KEY=<my-secret-access-key>
  ```

  Configure the aws-secret:
  
  ```bash
  kubectl create secret generic aws-secret --namespace kube-system --from-literal "key_id=${AWS_ACCESS_KEY_ID}" --from-literal "access_key=${AWS_SECRET_ACCESS_KEY}"
  ```

  Install the CSI driver:

  ```bash
  kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.20"
  ```

- Apply the storage class:

```bash
kubectl apply -f - <<-EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: tigera-elasticsearch
provisioner: ebs.csi.aws.com
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
EOF
```

### Calico Cloud Installation Steps

> :warning: **Ignore this section if going the Calico Enterprise route, refer to the previous section for those steps**

There needs to be a CNI present on the cluster before we connect it to Calico Cloud, so we will first install Calico OSS CNI on the cluster:

- Install the operator:

  ```kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/tigera-operator.yaml```

- Modify the the Calico Installation CR as needed with the correct pod CIDR, then install it for cluster-1:
  
  ```kubectl create -f manifests/cc-cluster-1-calico-installation.yaml```

### Adding worker nodes to the cluster

Regardless of whether Calico Enterprise was installed on the cluster, or Calico OSS CNI was installed on the cluster, worker nodes and the nodegroup need to be added to the cluster:

- Add worker nodes to the cluster using the values for the clustername and region as used from the ```eksctl-config-cluster-1.yaml``` file:
  
  ```bash
  eksctl create nodegroup --cluster <cluster_name> --region <region> --node-type <node_type> --max-pods-per-node 100 --nodes 2 --nodes-max 3 --nodes-min 2
  ```

- Monitor progress with ```kubectl get tigerastatus``` and once ```apiserver``` status shows ```Available```, proceed to the next steps depending on whether you installed Calico Enterprise or intend to join the cluster to Calico Cloud.

### Calico Enterprise Additional Steps

> :warning: **Ignore this section if going the Calico Cloud route, refer to the next section for those steps**

- Install the license file.

- Create a ```LoadBalancer``` service for the ```tigera-manager``` pods to access from your machine:

  ```bash
  kubectl create -f manifests/mgmt-cluster-lb.yaml
  ```

- Once the rest of the cluster comes up, configure user access to the manager UI with the docs [here](https://docs.tigera.io/calico-enterprise/next/operations/cnx/access-the-manager)

### Calico Cloud Additional Steps

> :warning: **Ignore this section if going the Calico Enterprise route, refer to the previous section for those steps**

- Now that worker nodes are added, we are ready to join the cluster to Calico Cloud

- [Connect a cluster to Calico Cloud](https://docs.tigera.io/calico-cloud/get-started/connect/install-cluster)

### Cluster-2 setup with ```eksctl```

[Reference](https://docs.tigera.io/calico-enterprise/next/getting-started/install-on-clusters/eks#install-eks-with-calico-networking)

- Change the values under ```manifests/eksctl-config-cluster2.yaml``` as needed. Note the VPC and svc cidrs.

- Create the cluster:

  ```bash
  eksctl create cluster -f manifests/eksctl-config-cluster2.yaml
  ```

- Once the cluster is up and you have ```kubectl``` access, delete the ```aws-node``` daemonset:

  ```bash
  kubectl delete daemonset -n kube-system aws-node
  ```

### Calico Enterprise Installation Steps

> :warning: **Ignore this section if going the Calico Cloud route, refer to the next section for those steps**

- Apply the operator and prometheus manifests from the repo:

  ```bash
  kubectl create -f https://downloads.tigera.io/ee/v3.18.0-2.0/manifests/tigera-operator.yaml
  ```

  ```bash
  kubectl create -f https://downloads.tigera.io/ee/v3.18.0-2.0/manifests/tigera-prometheus-operator.yaml
  ```

- Get a pull secret: The official build uses the quay.io images, so you'll need a pull secret. [This doc](https://tigera.atlassian.net/wiki/spaces/CS/pages/623575278/Creating+Pull+secrets+and+License+files+for+PoC+s) has options on how to generate one as per the official POC/testing process.

- Install the pull secret:
  
  ```bash
  kubectl create secret generic tigera-pull-secret --type=kubernetes.io/dockerconfigjson -n tigera-operator --from-file=.dockerconfigjson=<path/to/pull/secret>
  ```

- For the Prometheus operator, create the pull secret in the tigera-prometheus namespace and then patch the deployment

  ```bash
  kubectl create secret generic tigera-pull-secret --type=kubernetes.io/dockerconfigjson -n tigera-prometheus --from-file=.dockerconfigjson=<path/to/pull/secret>
  ```

  ```bash
  kubectl patch deployment -n tigera-prometheus calico-prometheus-operator -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name": "tigera-pull-secret"}]}}}}'
  ```

- Modify the ```managedcluster-custom-resources-example.yaml``` file as needed and apply it. In this case cluster-2 will be added to cluster-1 as a managed cluster so we omit all necessary components in the resources file, but ensure pod cidr is unique in the ```Installation``` resource.
  
  ```bash
  kubectl create -f manifests/managedcluster-custom-resources-example.yaml
  ```

### Calico Cloud Installation Steps

> :warning: **Ignore this section if going the Calico Enterprise route, refer to the previous section for those steps**

There needs to be a CNI present on the cluster before we connect it to Calico Cloud, so we will first install Calico OSS CNI on the cluster:

- Install the operator:

  ```kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/tigera-operator.yaml```

- Modify the the Calico Installation CR as needed with the correct pod CIDR, then install it for cluster-2:
  
  ```kubectl create -f manifests/cc-cluster-2-calico-installation.yaml```

### Adding worker nodes to the cluster

Regardless of whether Calico Enterprise was installed on the cluster, or Calico OSS CNI was installed on the cluster, worker nodes and the nodegroup need to be added to the cluster:

- Add nodes to the cluster using the values for the clustername and region as used from the ```eksctl-config-cluster-2.yaml``` file:
  
  ```bash
  eksctl create nodegroup --cluster <cluster_name> --region <region> --node-type <node_type> --max-pods-per-node 100 --nodes 2 --nodes-max 3 --nodes-min 2
  ```

- Monitor progress with ```kubectl get tigerastatus``` and once ```apiserver``` status shows ```Available```, install the license file.

### Calico Enterprise Additional Steps (adding MCM)

> :warning: **Ignore this section if going the Calico Cloud route, this is only required for Calico Enterprise**

Here we will add cluster-2 as a managed cluster to the mgmt. cluster of cluster-1:

- Create the mgmt cluster resources as per the [docs here](https://docs.tigera.io/calico-enterprise/latest/multicluster/create-a-management-cluster)

  An example of using another ```LoadBalancer``` svc to expose the MCM ```targetport``` of 9449 and using that for the managed cluster to access is at ```manifests/mcm-svc-lb.yaml```:

  ```bash
  kubectl create -f manifests/mcm-svc-lb.yaml
  ```

  If you prefer to use NodePort or Ingress type svc you can, but it is outside the scope of this README. Refer to the docs above.

  The latest nightly build before v3.18.0-2.0 release had an [issue](https://github.com/tigera/operator/pull/2948) with creating the ```ManagementClusterCR``` as per the docs manifest. The workaround here is kept just for historical purpose. When we get to the step to apply the ```ManagementClusterCR```, change the spec to have the ```.spec.tls.secretName``` set to ```tigera-management-cluster-connection``` , like so (replace ```.spec.address``` with your relevant svc URL and port):
  
  ```bash
  export MGMT_ADDRESS=<address-of-mcm-svc>:<port>
  ```

```bash
kubectl apply -f - <<-EOF
apiVersion: operator.tigera.io/v1
kind: ManagementCluster
metadata:
  name: tigera-secure
spec:
  address: $MGMT_ADDRESS
  tls:
    secretName: tigera-management-cluster-connection
EOF
```

  Ensure that the ```tigera-manager``` and ```tigera-linseed``` pods restart, and that the GUI of the mgmt. cluster shows the ```management-cluster``` in the right drop-down when the GUI svc comes back.
  
- Create the managed cluster resources as per the [docs here](https://docs.tigera.io/calico-enterprise/latest/multicluster/create-a-managed-cluster#create-the-connection-manifest-for-your-managed-cluster)

### Calico Cloud Additional Steps

> :warning: **Ignore this section if going the Calico Enterprise route, refer to the previous section for those steps**

- Now that worker nodes are added, we are ready to join the cluster to Calico Cloud

- [Connect a cluster to Calico Cloud](https://docs.tigera.io/calico-cloud/get-started/connect/install-cluster)

## VPC Peering

- [Doc on how to do this in the AWS console](https://docs.aws.amazon.com/vpc/latest/peering/create-vpc-peering-connection.html#same-account-different-region)

### Using AWS CLI and filters

> :warning: **Replace with your values as needed, these commands are just given as a guideline**

- Get the VPC IDs using the EKS cluster names

```bash
CLUSTER_A_VPC=$(aws ec2 describe-vpcs --region ca-central-1 --filters Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values="cc-eks-mcm1" --query "Vpcs[*].VpcId" --output text)
```

```bash
CLUSTER_B_VPC=$(aws ec2 describe-vpcs --region us-east-1 --filters Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values="cc-eks-mcm2" --query "Vpcs[*].VpcId" --output text)
```

- Generate VPC peering request

```bash
aws ec2 create-vpc-peering-connection --region ca-central-1 --vpc-id $CLUSTER_A_VPC --peer-vpc-id $CLUSTER_B_VPC --peer-region us-east-1 2>&1 > /dev/null
```

- Get the route table id for each cluster

```bash
ROUTE_ID_CA=$(aws ec2 describe-route-tables --region ca-central-1 --filters "Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=cc-eks-mcm1" "Name=tag:"aws:cloudformation:logical-id",Values="PublicRouteTable"" --query "RouteTables[*].RouteTableId" --output text)
```

```bash
ROUTE_ID_CB=$(aws ec2 describe-route-tables --region us-east-1 --filters "Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=cc-eks-mcm2" "Name=tag:"aws:cloudformation:logical-id",Values="PublicRouteTable"" --query "RouteTables[*].RouteTableId" --output text)
```

> :warning: **Depending on your setup, you may need to use different filters to get the correct route table id, this is just an example**

- Get the peering id

```bash
PEER_ID=$(aws ec2 describe-vpc-peering-connections --region ca-central-1 --query "VpcPeeringConnections[0].VpcPeeringConnectionId" --output text)
```

- Approve the peering request

```bash
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PEER_ID  --region us-east-1 2>&1
```

- Add the required routes to the route table for each VPC to its peer VPC CIDR as defined in the eksctl config file

```bash
aws ec2 create-route --region ca-central-1 --route-table-id $ROUTE_ID_CA --destination-cidr-block "10.10.0.0/24" --vpc-peering-connection-id $PEER_ID
```

```bash
aws ec2 create-route --region us-east-1 --route-table-id $ROUTE_ID_CB --destination-cidr-block "192.168.0.0/24" --vpc-peering-connection-id $PEER_ID
```

## Security Groups

- Ensure that as a minimum VXLAN UDP port 4789 is opened on both clusters for each other's VPC CIDR, and possibly ICMP if you want to run ping tests between pods in the two clusters.

## Cluster Mesh VXLAN setup (finally)

[Reference doc](https://docs.tigera.io/calico-enterprise/next/multicluster/federation/kubeconfig)

- Copy ```setup.env.example``` to ```setup.env``` and edit the values for the regions and contexts as needed.

- In the ```setup.env``` , add the cluster context names and regions of both the clusters as the federation install script will switch contexts and run the commands using kubectl.

- Run the script from this repo's root dir:

```bash
./install-federation-overlay.sh
```

## Check endpoints on a node with calicoq

Verifying that federated endpoints got created:

### Linux Users

- If your laptop/machine is Linux-based or you are running a Linux VM that is setup with access to your K8s clusters, then just download calicoq CLI tool from the [Calico docs](https://docs.tigera.io/calico-enterprise/3.15/operations/clis/calicoq/installing#install-calicoq-as-a-binary-on-a-single-host)
- Run the following command against your clusters:

```bash
calicoq eval "all()"
```

  You should get something like this where you see remote endpoints prefixed by the RemoteClusterConfig name you created in the earlier steps as well as local endpoints with the format host-a/endpoint:

  ```bash
  (Lots of remote endpoints)
  Workload endpoint ip-192-168-0-42.ca-central-1.compute.internal/k8s/tigera-policy-recommendation.tigera-policy-recommendation-575f55bcbd-n6x7k/eth0
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-23.ec2.internal/k8s/cartservice.cartservice-74b9768648-s8vwb/eth0
  Workload endpoint ip-192-168-0-80.ca-central-1.compute.internal/k8s/tigera-elasticsearch.tigera-linseed-75c5ffdf49-x6snw/eth0
  Workload endpoint ip-192-168-0-42.ca-central-1.compute.internal/k8s/tigera-prometheus.calico-prometheus-operator-75c5f765-9j4m4/eth0
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-23.ec2.internal/k8s/tigera-compliance.compliance-snapshotter-6cd6c76486-bmtkm/eth0
  Workload endpoint ip-192-168-0-42.ca-central-1.compute.internal/k8s/kube-system.ebs-csi-controller-f9566dbd6-6wpbw/eth0
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-23.ec2.internal/k8s/dev.dev-nginx-789ddfc8db-6dkms/eth0
  Workload endpoint ip-192-168-0-80.ca-central-1.compute.internal/k8s/tigera-compliance.compliance-benchmarker-zjknl/eth0
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-23.ec2.internal/k8s/calico-system.calico-kube-controllers-77ffffd989-klpzv/eth0
  Workload endpoint ip-192-168-0-42.ca-central-1.compute.internal/k8s/kube-system.ebs-csi-controller-f9566dbd6-v5cmk/eth0
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-23.ec2.internal/k8s/tigera-prometheus.prometheus-calico-node-prometheus-0/eth0
  Workload endpoint ip-192-168-0-42.ca-central-1.compute.internal/k8s/tigera-kibana.tigera-secure-kb-56d99cbdff-lnh92/eth0
  Workload endpoint ip-192-168-0-42.ca-central-1.compute.internal/k8s/calico-system.csi-node-driver-d6pgr/eth0
  ```

### MacOS/Windows Users

- If your laptop/machine is Darwin/MacOS or you use WSL, then we have to do things the hard way (REALLY annoying and bad security practice) by using a privileged debug pod on one of the cluster nodes to temporaily install calicoq and do our verification there because calicoq does not have a MacOS/Darwin binary yet. Just spin up a Linux VM anyway is the recommended method but read further if you really want to do this on Mac/Windows.

- Switch to your cluster context
- Get the nodename of one of the worker nodes and save it in a variable

```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'| awk '{print $1;}')
```

- Spin up a debug privileged pod

```bash
kubectl debug node/$NODE_NAME -it --image=ubuntu
```

- In the pod, get to host namespace as root

```bash
chroot /host
```

- Grab the calicoq binary and install it

```bash
cd /usr/local/bin
curl -o calicoq -O -L https://downloads.tigera.io/ee/binaries/v3.18.0-1.1/calicoq
chmod +x calicoq
```

- Make the Calico dir (if it doesn't exist) and create the config file for it

```bash
mkdir -p /etc/calico
vi /etc/calico/calicoq.cfg
```

Paste in the following:

```yaml
apiVersion: projectcalico.org/v3
kind: CalicoAPIConfig
metadata:
spec:
  datastoreType: "kubernetes"
  kubeconfig: "/.kube/config"
```

- Create the /.kube/config file, put your config file into it

```bash
mkdir -p /.kube
vi /.kube/config
```

Paste your kubeconfig for the cluster from your laptop's ~/.kube/config (or wherever you have it), save the file.

- Now run calicoq

```bash
calicoq eval "all()"
```

  You should get something like this where you see remote endpoints prefixed by the RemoteClusterConfig name you created in the earlier steps as well as local endpoints with the format host-a/endpoint:

  ```bash
  (Lots of remote endpoints)
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-23.ec2.internal/k8s/dev.netshoot/eth0
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-43.ec2.internal/k8s/default.centos/eth0
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-43.ec2.internal/k8s/dev.centos/eth0
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-43.ec2.internal/k8s/dev.dev-nginx-789ddfc8db-t85fk/eth0
  Workload endpoint calico-demo-remote-us-east-1/ip-10-10-0-23.ec2.internal/k8s/dev.dev-nginx-789ddfc8db-6dkms/eth0
  ```

## Verify IP routes to remote clusters

- First, get a debug privileged pod and check the routes on one of the worker nodes, there should be routes for the other cluster's pod cidr with the ```vxlan.calico``` interface

```bash
172.17.120.128/26 via 172.17.120.128 dev vxlan.calico onlink
172.17.202.0/26 via 172.17.202.0 dev vxlan.calico onlink
```

## Troubleshooting Federation Configurations

- Refer to the [troubleshooting section](https://docs.tigera.io/calico-enterprise/next/multicluster/federation/kubeconfig#troubleshoot) of the ```next``` docs

> :warning: **Someday I'll automate this with Terraform or something**

## Demo Env Prep

- Deploy the different application stacks on the clusters as below:
  
  Cluster-1:

  ```bash
  kubectl create -f demo-apps/00-namespaces.yaml
  kubectl create -f demo-apps/10-stars.yaml
  kubectl create -f demo-apps/40-nginx-deploy.yaml
  ```

  Cluster-2:

  ```bash
  kubectl create -f demo-apps/00-namespaces.yaml
  kubectl create -f demo-apps/20-hipstershop-app.yaml
  kubectl create -f demo-apps/30-dev-app.yaml
  kubectl create -f demo-apps/40-nginx-deploy.yaml
  ```

- The demo environment implements a zone-based architecture across the clusters with three major applications - stars,dev-nginx and hipstershop:

  Cluster-1:

  In cluster-1, we have the ```stars``` app pods labeled with ```zone=app1```
  Run the following command to see this:

  ```bash
  kubectl get pod -A -l zone=app1 -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"
  ```

  We should get all of the ```zone=app1``` pods across the namespaces:

  ```bash
  POD-NAME                         NAMESPACE       IP               POD-LABELS
  client-d668c86bf-sdc55           client          172.16.82.20     map[pod-template-hash:d668c86bf role:client zone:app1]
  management-ui-6795d4f59c-h2ncq   management-ui   172.16.163.158   map[pod-template-hash:6795d4f59c role:management-ui zone:app1]
  backend-8678866bb7-rxq6m         stars           172.16.163.156   map[pod-template-hash:8678866bb7 role:backend zone:app1]
  frontend-595f6d847-ss9v7         stars           172.16.163.157   map[pod-template-hash:595f6d847 role:frontend zone:app1]
  ```

  Cluster-2:

  In cluster-2, we have the ```dev``` pods labeled as ```zone=shared``` and the ```hipstershop``` app pods labeled as ```zone=app2```

  Run the following command to see all the pods labeled as ```zone=shared```

  ```bash
  kubectl get pod -A -l zone=shared -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"
  ```

  ```bash
  POD-NAME                     NAMESPACE   IP               POD-LABELS
  centos                       default     172.17.226.144   map[app:centos zone:shared]
  centos                       dev         172.17.64.19     map[app:centos zone:shared]
  dev-nginx-8564bf5476-2xpff   dev         172.17.64.20     map[app:nginx pod-template-hash:8564bf5476 security:strict zone:shared]
  dev-nginx-8564bf5476-kgbbp   dev         172.17.226.143   map[app:nginx pod-template-hash:8564bf5476 security:strict zone:shared]
  netshoot                     dev         172.17.64.21     map[app:netshoot zone:shared]
  ```

  Run the following command to see all the hipstershop app pods labeled as ```zone=app2```

  ```bash
  kubectl get pod -A -l zone=app2 -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"
  ```

  ```bash
  POD-NAME                                 NAMESPACE               IP               POD-LABELS
  adservice-76488669b-jvtb7                adservice               172.17.226.142   map[app:adservice pod-template-hash:76488669b zone:app2]
  cartservice-86648449bb-fzr9h             cartservice             172.17.64.16     map[app:cartservice pod-template-hash:86648449bb zone:app2]
  checkoutservice-c9759c6cf-x9vxb          checkoutservice         172.17.64.11     map[app:checkoutservice pod-template-hash:c9759c6cf zone:app2]
  currencyservice-84b75b6b94-fn8mj         currencyservice         172.17.64.17     map[app:currencyservice pod-template-hash:84b75b6b94 zone:app2]
  emailservice-8666d6bbb6-dbbx6            emailservice            172.17.64.10     map[app:emailservice pod-template-hash:8666d6bbb6 zone:app2]
  frontend-6c6f577957-lzk9w                frontend                172.17.64.13     map[app:frontend pod-template-hash:6c6f577957 zone:app2]
  loadgenerator-8cdf78b5d-nd8h8            loadgenerator           172.17.64.23     map[app:loadgenerator pod-template-hash:8cdf78b5d zone:app2]
  paymentservice-5f8d6b68cd-bwz2b          paymentservice          172.17.64.14     map[app:paymentservice pod-template-hash:5f8d6b68cd zone:app2]
  productcatalogservice-58f5c6c474-b24dq   productcatalogservice   172.17.64.15     map[app:productcatalogservice pod-template-hash:58f5c6c474 zone:app2]
  recommendationservice-66df778ccc-7q59p   recommendationservice   172.17.64.12     map[app:recommendationservice pod-template-hash:66df778ccc zone:app2]
  redis-cart-7844cf686f-zs7vl              redis-cart              172.17.226.141   map[app:redis-cart pod-template-hash:7844cf686f zone:app2]
  shippingservice-8957d5b7b-wxsfg          shippingservice         172.17.64.18     map[app:shippingservice pod-template-hash:8957d5b7b zone:app2]
  ```

## Testing cross-cluster pod-to-pod communication

Here we will run some traffic flow tests by doing ```kubectl exec``` into pods

- Test traffic from the ```client``` pod in ```client``` namespace on cluster-1 to the ```frontend``` pod in cluster-2:
  
  - First, determine the IP of the ```frontend``` endpoint in cluster-2 by running the following command on cluster-2:

    ```bash
    kubectl get endpoints -n frontend frontend
    ```

    This should give an output similar to:

    ```bash
    NAME       ENDPOINTS           AGE
    frontend   172.17.64.13:8080   47h
    ```

    > :warning: **The endpoint IP will be different in your cluster, the above output is just an example**

  - Next, execute the ```curl``` command on the ```client``` pod in ```client``` namespace on cluster-1:
  
    > :warning: **Substitute the \<frontend-endpoint-ip\>:\<port\> with the value from your cluster from the previous command**

    ```bash
    kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<frontend-endpoint-ip>:<port>'
    ```

    You should get a successful response from the ```frontend``` pod in cluster-2 like so:

    ```bash
    HTTP/1.1 200 OK
    Set-Cookie: shop_session-id=38c6c7be-e731-4048-a070-c94fbc1253b4; Max-Age=172800
    Date: Thu, 30 Nov 2023 20:07:21 GMT
    Content-Type: text/html; charset=utf-8
    ```

- Test traffic from the ```client``` pod in ```client``` namespace on cluster-1 to one of the ```nginx``` pods in the ```dev``` namespace in cluster-2:

  - First, determine the IPs of the ```nginx-svc``` endpoints in cluster-2 by running the following command on cluster-2:

    ```bash
    kubectl get endpoints -n dev nginx-svc
    ```

    This should give an output similar to:

    ```bash
    NAME        ENDPOINTS                           AGE
    nginx-svc   172.17.226.143:80,172.17.64.20:80   2d
    ```

    > :warning: **The endpoint IP will be different in your cluster, the above output is just an example**

  - Next, execute the ```curl``` command on the ```client``` pod in ```client``` namespace on cluster-1 to one of the ```nginx-svc``` endpoints:

    ```bash
    kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<nginx-svc-endpoint-ip>:<port>'
    ```

    You should get a successful response from the ```nginx-svc``` pod like so:

    ```bash
    HTTP/1.1 200 OK
    Server: nginx/1.25.3
    Date: Thu, 30 Nov 2023 20:43:34 GMT
    Content-Type: text/html
    Content-Length: 615
    Last-Modified: Tue, 24 Oct 2023 13:46:47 GMT
    Connection: keep-alive
    ETag: "6537cac7-267"
    Accept-Ranges: bytes
    ```

## Testing Federated Endpoint Policy

### Overview

In this demo, we will be enforcing the following network policy posture:

![zones_png](https://github.com/tigera-solutions/cent-mcm-overlay/assets/117195889/ac4f78dc-218d-4ee8-9b2e-26d44911fcca)

### Apply Policies

- On cluster-1, apply the policies:
  
  ```kubectl create -f federated-policy/cluster-1-policy```

- On cluster-2, apply the policies:

  ```kubectl create -f federated-policy/cluster-2-policy```

- Check the policy board and enforce the ```default-deny``` staged policy on both clusters.

### Test Policies

- On cluster-2, get the IP of one of the nginx pods in the ```zone == shared``` set of workloads:
  
  ```kubectl get pod -A -l zone=shared -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"```

- On cluster-1, exec into the shell of the ```client``` pod and try to hit the pod IP from the previous step:

  ```kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<dest-pod-IP>>:<port>'```

  The response should return a HTTP 200 OK as the policy should allow the traffic.

- Look at the flow on the service graph in Calico Cloud to understand the flow log and to confirm the policies that were evaluated by Calico to allow the flow to the destination pod.

- On cluster-2, get the IP of one of the ```frontend``` pods in the ```zone == app2``` set of workloads:
  
  ```kubectl get pod -A -l zone=app2 -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"```

- On cluster-1, exec into the shell of the ```client``` pod and try to hit the pod IP from the previous step:

  ```kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<dest-pod-IP>>:<port>'```

  This flow to the ```frontend``` pod IP should fail and timeout due to the policy denying flows to ```zone=app2```

- Look at the flow on the service graph in Calico Cloud to understand the flow log and to confirm the policies that were evaluated by Calico to deny the flow to the destination pod.
