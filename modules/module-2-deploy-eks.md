# Module 2 - Deploy the EKS Clusters

## Prerequisites

In order to be able to setup the VXLAN Cluster Mesh:

- There will need to be two EKS clusters running Calico CNI, this is done in different regions with VPC peering to peer the node CIDRs.
- VPC/node subnet CIDRs for each cluster will need to be unique to allow worker node peering to happen, and pod cidrs and svc cidrs also need to be unique for each cluster. This is set in the eksctl config file and the Calico Installation custom resources config file respectively.
- [Clustermesh setup docs](https://docs.tigera.io/calico-cloud/multicluster/kubeconfig)

## Steps

Following steps are done for a 2-cluster setup using eksctl from a config file

### Configure variables

- Set `CLUSTER1_REGION` and `CLUSTER2_REGION` variables that will be used to set regions in which you want to build EKS clusters

  ```bash
  CLUSTER1_REGION=ca-central-1
  CLUSTER2_REGION=us-east-1
  EKS_VERSION=1.29
  ```

- Check available `availability zones` for the regions you plan to build clusters in

  ```bash
  aws ec2 describe-availability-zones --region $CLUSTER1_REGION --query '*[].ZoneName' --output table
  aws ec2 describe-availability-zones --region $CLUSTER2_REGION --query '*[].ZoneName' --output table
  ```

- Set availability zones for each cluster

  ```bash
  # set availability zones for CLUSTER1
  indx=0
  for az in $(aws ec2 describe-availability-zones --region $CLUSTER1_REGION --query '*[].ZoneName' --output text); do
    if [[ $indx == 0 ]]; then 
      CLUSTER1_AZ_LIST="\"$az\""
    else
      CLUSTER1_AZ_LIST="$CLUSTER1_AZ_LIST,\"$az\""
    fi 
    ((indx++))
  done;

  # set availability zones for CLUSTER2
  indx=0
  for az in $(aws ec2 describe-availability-zones --region $CLUSTER2_REGION --query '*[].ZoneName' --output text); do
    if [[ $indx == 0 ]]; then 
      CLUSTER2_AZ_LIST="\"$az\""
    else
      CLUSTER2_AZ_LIST="$CLUSTER2_AZ_LIST,\"$az\""
    fi 
    ((indx++))
  done;
  ```

### Cluster-1 initial setup with ```eksctl```

[Reference](https://docs.tigera.io/calico-enterprise/next/getting-started/install-on-clusters/eks#install-eks-with-calico-networking)

- Review ```manifests/eksctl-config-cluster1.yaml``` manifest and adjust the values as needed. Note the **unique** VPC and svc cidrs.

- Create the cluster in the desired region:

  ```bash
  sed -e "s/\${CLUSTER_REGION}/${CLUSTER1_REGION}/g" -e "s/\${EKS_VERSION}/${EKS_VERSION}/g" -e "s/\${CLUSTER_AZS}/${CLUSTER1_AZ_LIST}/g" manifests/eksctl-config-cluster1.yaml | eksctl create cluster -f-
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
  sed -e "s/\${CLUSTER_REGION}/${CLUSTER2_REGION}/g" -e "s/\${EKS_VERSION}/${EKS_VERSION}/g" -e "s/\${CLUSTER_AZS}/${CLUSTER2_AZ_LIST}/g" manifests/eksctl-config-cluster2.yaml | eksctl create cluster -f-
  ```

- The next step is to prepare the clusters for installing Calico Cloud or Enterprise:

  - If deciding to go with Calico Enterprise installation, go here:

    [:arrow_right: Module 3.1 - Install Calico Enterprise](module-3.1-install-calient-mgmt.md)

  - If deciding to go with setting up the clusters to connect to a Calico Cloud instace, go here:

    [:arrow_right: Module 3.2 - Setup clusters and connect to Calico Cloud](module-3.2-cc-setup.md)

[:arrow_left: Module 1 - Getting Started](module-1-getting-started.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
