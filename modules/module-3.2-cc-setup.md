# Module 3.2 - Setup clusters and connect to Calico Cloud

> :warning: **Ignore this section if going the Calico Enterprise route, refer to [this section](module-3.1-install-calient-mgmt.md) for the steps instead**

## Overview

- There needs to be a CNI present on the cluster before we connect it to Calico Cloud, so we will first install Calico OSS CNI on the clusters.

### Configure variables

- Set `CLUSTER1_NAME`, `CLUSTER2_NAME`, and `NODE_TYPE` variables that will be used to set regions in which you want to build EKS clusters

  >Note that `CLUSTER1_REGION` and `CLUSTER2_REGION` variables were set in one of the previous modules. If not, make sure to set the same region values as were used to build the clusters.

  ```bash
  CLUSTER1_NAME=cc-eks-mcm1
  CLUSTER2_NAME=cc-eks-mcm2
  NODE_TYPE="t3.large"
  ```

## Cluster-1 Installation Steps

- Install the Tigera OSS operator manifest:

  ```kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml```

- Modify the the Calico Installation CR file as needed with the correct pod CIDR, then install it for cluster-1:
  
  ```kubectl create -f manifests/cc-cluster-1-calico-installation.yaml```

- Set variables

  ```bash
  CLUSTERNAME=cc-eks-mcm1
  CLUSTER1_REGION=ca-central-1
  ```

- Add worker nodes to the cluster using the values for the clustername and region as used from the ```eksctl-config-cluster-1.yaml``` file:

  ```bash
  eksctl create nodegroup --cluster $CLUSTER1_NAME --region $CLUSTER1_REGION --node-type $NODE_TYPE --max-pods-per-node 100 --nodes 2 --nodes-max 3 --nodes-min 2
  ```

- Once EKS has added the worker nodes to the cluster and the output of ```kubectl get nodes``` shows the nodes as available, monitor progress of all the pods as well as the output of ```kubectl get tigerastatus``` and ensure that the ```apiserver``` status shows ```Available```

- Now that worker nodes are added, we are ready to join the cluster to Calico Cloud:

  [Connect a cluster to Calico Cloud](https://docs.tigera.io/calico-cloud/get-started/connect/install-cluster)

## Cluster-2 Installation Steps

- Install the Tigera OSS operator manifest:

  ```kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml```

- Modify the the Calico Installation CR file as needed with the correct pod CIDR, then install it for cluster-1:
  
  ```kubectl create -f manifests/cc-cluster-2-calico-installation.yaml```

- Add worker nodes to the cluster using the values for the clustername and region as used from the ```eksctl-config-cluster-1.yaml``` file:

    ```bash
  eksctl create nodegroup --cluster $CLUSTER2_NAME --region $CLUSTER2_REGION --node-type $NODE_TYPE --max-pods-per-node 100 --nodes 2 --nodes-max 3 --nodes-min 2
  ```

- Once EKS has added the worker nodes to the cluster and the output of ```kubectl get nodes``` shows the nodes as available, monitor progress of all the pods as well as the output of ```kubectl get tigerastatus``` and ensure that the ```apiserver``` status shows ```Available```

- Now that worker nodes are added, we are ready to join the cluster to Calico Cloud:

  [Connect a cluster to Calico Cloud](https://docs.tigera.io/calico-cloud/get-started/connect/install-cluster)

[:arrow_right: Module 4 - Setup VPC Peering](module-4-setup-vpcpeering.md)  
[:arrow_left: Module 2 - Deploy the EKS Clusters](module-2-deploy-eks.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
