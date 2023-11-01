# EKS Cluster mesh setup in Overlay/VXLAN mode on Calico Enterprise

> :warning: **This repo is purely a work-in-progress(WIP) and is in active development. Other than contributors, anyone else should probably not try the stuff in this repo and expect it to work as is until it's finished and ready!**

For reference, this uses the nightly build [here](https://2023-10-12-master-swagger.docs.eng.tigera.net/manifests/) for the files that are in the ```manifests``` folder.

## Notes

- There will need to be two EKS clusters running Calico CNI, this is done in different regions with VPC peering to peer the node CIDRs.
- VPC CIDRs for each cluster will need to be unique to allow peering to happen, and pod cidrs and svc cidrs also need to be unique for each cluster. This is set in the eksctl config file and the Calico custom resources config file respectively.
- [Next doc for clustermesh](https://docs.tigera.io/calico-enterprise/next/multicluster/federation/kubeconfig)

## Steps

Following steps are done for a 2-cluster setup using eksctl from a config file

### Cluster-1 setup with ```eksctl```

[Reference](https://docs.tigera.io/calico-enterprise/next/getting-started/install-on-clusters/eks#install-eks-with-calico-networking)

- Change the values under ```manifests/eksctl-config-cluster-1.yaml``` as needed. Note the VPC and svc cidrs.

- Create the cluster:
  ```eksctl create cluster -f manifests/eksctl-config-cluster-1.yaml```

- Once the cluster is up and you have ```kubectl``` access, delete the ```aws-node``` daemonset:
  ```kubectl delete daemonset -n kube-system aws-node```

- Apply the operator and prometheus manifests from the repo:
  ```kubectl create -f manifests/tigera-operator.yaml```
  ```kubectl create -f manifests/tigera-prometheus-operator.yaml```

- Get a pull secret: The nightly build uses the GCR images, so you'll need a gcr.io pull secret. [This doc](https://tigera.atlassian.net/wiki/spaces/ENG/pages/456589334/Pull+Secrets+for+GCR) has options on how to get one.

- Install the pull secret:
  
  ```kubectl create secret generic tigera-pull-secret --type=kubernetes.io/dockerconfigjson -n tigera-operator --from-file=.dockerconfigjson=<path/to/pull/secret>```

- Modify the ```mgmtcluster-custom-resources-example.yaml``` file as needed and apply it.
  
  ```kubectl create -f manifests/mgmtcluster-custom-resources-example.yaml```

- For ```LogStorage``` , install the EBS CSI driver: [EBS on EKS docs reference](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)

- Apply the storage class:

  ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
    name: tigera-elasticsearch
    provisioner: ebs.csi.aws.com
    reclaimPolicy: Retain
    allowVolumeExpansion: true
    volumeBindingMode: WaitForFirstConsumer
  ```

- Add nodes to the cluster using the values for the clustername and region as used from the ```eksctl-config-cluster-1.yaml``` file:
  
  ```eksctl create nodegroup --cluster <cluster_name> --region <region> --node-type <node_type> --max-pods-per-node 100 --nodes 2 --nodes-max 3 --nodes-min 2```

- Monitor progress with ```kubectl get tigerastatus``` and once ```apiserver``` status shows ```Available```, install the license file.

- Once the rest of the cluster comes up, configure access to the manager UI with the docs [here](https://docs.tigera.io/calico-enterprise/next/operations/cnx/access-the-manager)

### Cluster-2 setup with ```eksctl```

[Reference](https://docs.tigera.io/calico-enterprise/next/getting-started/install-on-clusters/eks#install-eks-with-calico-networking)

- Change the values under ```manifests/eksctl-config-cluster-2.yaml``` as needed. Note the VPC and svc cidrs.

- Create the cluster:
  ```eksctl create cluster -f manifests/eksctl-config-cluster-2.yaml```

- Once the cluster is up and you have ```kubectl``` access, delete the ```aws-node``` daemonset:
  ```kubectl delete daemonset -n kube-system aws-node```

- Apply the operator and prometheus manifests from the repo:
  ```kubectl create -f manifests/tigera-operator.yaml```
  ```kubectl create -f manifests/tigera-prometheus-operator.yaml```

- Get a pull secret: The nightly build uses the GCR images, so you'll need a gcr.io pull secret. [This doc](https://tigera.atlassian.net/wiki/spaces/ENG/pages/456589334/Pull+Secrets+for+GCR) has options on how to get one.

- Install the pull secret:
  
  ```kubectl create secret generic tigera-pull-secret --type=kubernetes.io/dockerconfigjson -n tigera-operator --from-file=.dockerconfigjson=<path/to/pull/secret>```

- Modify the ```mgmtcluster-custom-resources-example.yaml``` file as needed and apply it. In this case cluster-2 will be added to cluster-1 as a managed cluster so we omit all necessary components in the resources file, but ensure pod cidr is unique in the ```Installation``` resource.
  
  ```kubectl create -f manifests/mgmtcluster-custom-resources-example.yaml```

- Add nodes to the cluster using the values for the clustername and region as used from the ```eksctl-config-cluster-2.yaml``` file:
  
  ```eksctl create nodegroup --cluster <cluster_name> --region <region> --node-type <node_type> --max-pods-per-node 100 --nodes 2 --nodes-max 3 --nodes-min 2```

- Monitor progress with ```kubectl get tigerastatus``` and once ```apiserver``` status shows ```Available```, install the license file.

## MCM setup

- Create the mgmt cluster resources as per the [docs here](https://docs.tigera.io/calico-enterprise/latest/multicluster/create-a-management-cluster)
  
- Create the managed cluster resources as per the [docs here](https://docs.tigera.io/calico-enterprise/latest/multicluster/create-a-managed-cluster#create-the-connection-manifest-for-your-managed-cluster)

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

- In the ```setup.env``` , add the cluster context names and regions of both the clusters as the federation install script will switch contexts and run the commands using kubectl.

- Run the script from the root dir:

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
kubectl debug node/$NODE_NAME -it --image=mcr.microsoft.com/aks/fundamental/base-ubuntu:v0.0.11
```

- In the pod, get to host namespace as root

```bash
chroot /host
```

- Grab the calicoq binary and install it

```bash
cd /usr/local/bin
curl -o calicoq -O -L https://downloads.tigera.io/ee/binaries/v3.15.1/calicoq
chmod +x calicoq
```

- Create the config file for it

```bash
vi /etc/calico/calicoctl.cfg
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
mkdir /.kube
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

## Verify pod-to-pod connectivity

- First, get a debug privileged pod and check the routes on one of the worker nodes, there should be routes for the other cluster's pod cidr with the ```vxlan.calico``` interface

```bash
172.17.120.128/26 via 172.17.120.128 dev vxlan.calico onlink
172.17.202.0/26 via 172.17.202.0 dev vxlan.calico onlink
```

- Ping from a pod in cluster-a to a pod IP in cluster-b

## Troubleshooting

- Refer to the [troubleshooting section](https://docs.tigera.io/calico-enterprise/next/multicluster/federation/kubeconfig#troubleshoot) of the ```next``` docs

> :warning: **Someday I'll automate this with Terraform or something**
