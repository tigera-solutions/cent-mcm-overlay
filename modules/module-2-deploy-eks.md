# Module 2 - Deploy the EKS Clusters

## Prerequisites

In order to be able to setup the VXLAN Cluster Mesh:

- There will need to be two EKS clusters running Calico CNI, this is done in different regions with VPC peering to peer the node CIDRs.
- VPC/node subnet CIDRs for each cluster will need to be unique to allow worker node peering to happen, and pod cidrs and svc cidrs also need to be unique for each cluster. This is set in the eksctl config file and the Calico Installation custom resources config file respectively.
- [Clustermesh setup docs](https://docs.tigera.io/calico-cloud/multicluster/kubeconfig)

## Steps

Following steps are done for a 2-cluster setup using eksctl from a config file

### Cluster-1 initial setup with ```eksctl```

[Reference](https://docs.tigera.io/calico-enterprise/next/getting-started/install-on-clusters/eks#install-eks-with-calico-networking)

- Change the values under ```manifests/eksctl-config-cluster1.yaml``` as needed. Note the **unique** VPC and svc cidrs.

- Create the cluster:

  ```bash
  eksctl create cluster -f manifests/eksctl-config-cluster1.yaml
  ```

- Once the cluster is up and you have ```kubectl``` access, delete the ```aws-node``` daemonset:
  
  ```bash
  kubectl delete daemonset -n kube-system aws-node
  ```

### Cluster-2 initial setup with ```eksctl```

[Reference](https://docs.tigera.io/calico-enterprise/next/getting-started/install-on-clusters/eks#install-eks-with-calico-networking)

- Change the values under ```manifests/eksctl-config-cluster2.yaml``` as needed. Note the **unique** VPC and svc cidrs.

- Create the cluster:

  ```bash
  eksctl create cluster -f manifests/eksctl-config-cluster2.yaml
  ```

- Once the cluster is up and you have ```kubectl``` access, delete the ```aws-node``` daemonset:

  ```bash
  kubectl delete daemonset -n kube-system aws-node
  ```

- The next step is to prepare the clusters for installing Calico Cloud or Enterprise:

  - If deciding to go with Calico Enterprise installation, go here:

    [:arrow_right: Module 3.1 - Install Calico Enterprise](module-3.1-install-calient-mgmt.md)

  - If deciding to go with setting up the clusters to connect to a Calico Cloud instace, go here:

    [:arrow_right: Module 3.2 - Setup clusters and connect to Calico Cloud](module-3.2-cc-setup.md)

[:leftwards_arrow_with_hook: Back to Main](../README.md)
