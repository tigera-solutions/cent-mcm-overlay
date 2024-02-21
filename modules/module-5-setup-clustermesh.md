# Module 5 - Setup VXLAN Cluster Mesh

## Using the VXLAN Cluster Mesh Install Script

[Reference doc](https://docs.tigera.io/calico-enterprise/next/multicluster/federation/kubeconfig)

- Copy ```setup.env.example``` to ```setup.env``` and edit the values for the regions and contexts as needed.

- In the ```setup.env``` , add the K8s cluster context names and regions of both the clusters as the federation install script will switch cluster contexts and run the commands using kubectl.

- Run the script from this repo's root dir:

```bash
./install-federation-overlay.sh
```

## Check endpoints on a node with calicoq

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

- Paste in the following:

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

- Paste your kubeconfig for the cluster from your laptop's ~/.kube/config (or wherever you have it), save the file.

- Run ```aws configure``` and [setup your identity](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html#cli-configure-files-methods) on that node to the AWS CLI so that calicoq can actually call to AWS and authenticate the identity with the kubeconfig file.

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

- Repeat this verification process from cluster-2 to verify that the remote endpoints got created for cluster-1 as well.

## Verify IP routes to remote clusters

- You can also get a debug privileged pod and check the routes on one of the worker nodes, there should be routes for the other cluster's pod cidr with the ```vxlan.calico``` interface:

```bash
172.17.120.128/26 via 172.17.120.128 dev vxlan.calico onlink
172.17.202.0/26 via 172.17.202.0 dev vxlan.calico onlink
```

## Troubleshooting Federation Configurations

- Refer to the [troubleshooting section](https://docs.tigera.io/calico-cloud/multicluster/kubeconfig#troubleshoot) of the docs.

[:arrow_right: Module 6 - Install Demo Apps](module-6-install-demo-apps.md) <br>

[:leftwards_arrow_with_hook: Back to Main](../README.md)