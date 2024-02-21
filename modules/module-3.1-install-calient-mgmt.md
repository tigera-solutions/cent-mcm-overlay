# Module 3.1 - Install Calico Enterprise

> :warning: **Ignore this section if going the Calico Cloud route, refer to [this section](module-3.2-cc-setup.md) for the steps instead**

## Overview

- Cluster-1 will act as the mgmt. cluster and we will enable MCM with cluster-2 being added as a managed cluster.

## Cluster-1 Installation Steps

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

- Add worker nodes to the cluster using the values for the clustername and region as used from the ```eksctl-config-cluster-1.yaml``` file:
  
  ```bash
  eksctl create nodegroup --cluster <cluster_name> --region <region> --node-type <node_type> --max-pods-per-node 100 --nodes 2 --nodes-max 3 --nodes-min 2
  ```

- Once EKS has added the worker nodes to the cluster and the output of ```kubectl get nodes``` shows the nodes as available, monitor progress of all the pods as well as the output of ```kubectl get tigerastatus``` and once ```apiserver``` status shows ```Available```, proceed to the next step.

- Install the Tigera license file.

- Once the rest of the cluster comes up, Create a ```LoadBalancer``` service for the ```tigera-manager``` pods to access from your machine:

  ```bash
  kubectl create -f manifests/mgmt-cluster-lb.yaml
  ```
  
- Configure user access to the manager UI with the docs [here](https://docs.tigera.io/calico-enterprise/next/operations/cnx/access-the-manager)

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

## Cluster-2 Installation Steps

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

- Add worker nodes to the cluster using the values for the clustername and region as used from the ```eksctl-config-cluster-1.yaml``` file:
  
  ```bash
  eksctl create nodegroup --cluster <cluster_name> --region <region> --node-type <node_type> --max-pods-per-node 100 --nodes 2 --nodes-max 3 --nodes-min 2
  ```

- Once EKS has added the worker nodes to the cluster and the output of ```kubectl get nodes``` shows the nodes as available, monitor progress of all the pods as well as the output of ```kubectl get tigerastatus``` and once ```apiserver``` status shows ```Available```, proceed to the next step.
  
- Create the managed cluster resources as per the [docs here](https://docs.tigera.io/calico-enterprise/latest/multicluster/create-a-managed-cluster#create-the-connection-manifest-for-your-managed-cluster)

[:arrow_right: Module 4 - Setup VPC Peering](module-4-setup-vpcpeering.md) <br>

[:leftwards_arrow_with_hook: Back to Main](../README.md)
