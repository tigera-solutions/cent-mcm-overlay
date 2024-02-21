# Module 4 - Setup VPC Peering

- [Doc on how to do this in the AWS console](https://docs.aws.amazon.com/vpc/latest/peering/create-vpc-peering-connection.html#same-account-different-region)

## Using AWS CLI and filters

> :warning: **Replace with your values as needed, these commands are just given as a guideline**

- Get the VPC IDs using the EKS cluster names:

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

## Setup Security Groups

- Ensure that as a minimum VXLAN UDP port 4789 is opened on both clusters for each other's VPC CIDR, and possibly ICMP if you want to run ping tests between pods in the two clusters.

[:arrow_right: Module 5 - Setup VXLAN Cluster Mesh](module-5-setup-clustermesh.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
