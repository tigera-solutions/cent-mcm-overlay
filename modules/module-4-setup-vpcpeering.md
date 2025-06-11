# Module 4 - Setup VPC Peering

## Using the AWS Console

- [Official AWS docs](https://docs.aws.amazon.com/vpc/latest/peering/create-vpc-peering-connection.html#same-account-different-region) on how to do this.

## Using AWS CLI and filters

> :warning: **Replace with your values as needed, these commands are just given as a guideline**

> [!NOTE]
> the `CLUSTER1_NAME`, `CLUSTER2_NAME`, `CLUSTER1_REGION` and `CLUSTER2_REGION` variables were set in previous modules

- Get the VPC IDs using the EKS cluster names:

```bash
CLUSTER_A_VPC=$(aws ec2 describe-vpcs --region $CLUSTER1_REGION --filters Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values="$CLUSTER1_NAME" --query "Vpcs[*].VpcId" --output text)
```

```bash
CLUSTER_B_VPC=$(aws ec2 describe-vpcs --region $CLUSTER2_REGION --filters Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values="$CLUSTER2_NAME" --query "Vpcs[*].VpcId" --output text)
```

- Generate VPC peering request

```bash
aws ec2 create-vpc-peering-connection --region $CLUSTER1_REGION --vpc-id $CLUSTER_A_VPC --peer-vpc-id $CLUSTER_B_VPC --peer-region $CLUSTER2_REGION 2>&1 > /dev/null
```

- Get the route table id for each cluster

```bash
ROUTE_ID_CA=$(aws ec2 describe-route-tables --region $CLUSTER1_REGION --filters "Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=$CLUSTER1_NAME" "Name=tag:"aws:cloudformation:logical-id",Values="PublicRouteTable"" --query "RouteTables[*].RouteTableId" --output text)
```

```bash
ROUTE_ID_CB=$(aws ec2 describe-route-tables --region $CLUSTER2_REGION --filters "Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=$CLUSTER2_NAME" "Name=tag:"aws:cloudformation:logical-id",Values="PublicRouteTable"" --query "RouteTables[*].RouteTableId" --output text)
```

> :warning: **Depending on your setup, you may need to use different filters to get the correct route table id, this is just an example**

- Get the peering id

```bash
PEER_ID=$(aws ec2 describe-vpc-peering-connections --region $CLUSTER1_REGION --query "VpcPeeringConnections[0].VpcPeeringConnectionId" --output text)
```

- Approve the peering request

```bash
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PEER_ID  --region $CLUSTER2_REGION 2>&1
```

- Add the required routes to the route table for each VPC to its peer VPC CIDR as defined in the eksctl config file

```bash
aws ec2 create-route --region $CLUSTER1_REGION --route-table-id $ROUTE_ID_CA --destination-cidr-block "10.10.0.0/24" --vpc-peering-connection-id $PEER_ID
```

```bash
aws ec2 create-route --region $CLUSTER2_REGION --route-table-id $ROUTE_ID_CB --destination-cidr-block "192.168.0.0/24" --vpc-peering-connection-id $PEER_ID
```

## Setup Security Groups and disable interface source-destination check

- Ensure that as a minimum VXLAN UDP port 4789 is opened on both clusters for each other's VPC CIDR, and possibly ICMP if you want to run ping tests between pods in the two clusters.

```bash
# get security group for CLUSTER1_NAME
SG1_ID=$(aws ec2 describe-instances --region $CLUSTER1_REGION --filters "Name=tag:Name,Values=*$CLUSTER1_NAME*" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[*].NetworkInterfaces[0].Groups[0].GroupId' --output text)
# get security group for CLUSTER2_NAME
SG2_ID=$(aws ec2 describe-instances --region $CLUSTER2_REGION --filters "Name=tag:Name,Values=*$CLUSTER2_NAME*" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[*].NetworkInterfaces[0].Groups[0].GroupId' --output text)

# allow UDP traffic over port 4789 for CLUSTER1_NAME and CLUSTER2_NAME
aws ec2 authorize-security-group-ingress --region $CLUSTER1_REGION --group-id $SG1_ID --protocol udp --port 4789 --cidr 10.10.0.0/16 2>&1 > /dev/null
aws ec2 authorize-security-group-ingress --region $CLUSTER2_REGION --group-id $SG2_ID --protocol udp --port 4789 --cidr 192.168.0.0/16 2>&1 > /dev/null
```

- Ensure that [source-destination check is disabled](https://docs.aws.amazon.com/vpc/latest/userguide/work-with-nat-instances.html#EIP_Disable_SrcDestCheck) in the interfaces of all of the worker nodes so that traffic originating from a peered VPC subnet is not dropped by the receiving node interface in a local VPC.

>Depending on how networking is configured in your VPCs, disabling `src/dest check` may not be necessary.

[:arrow_right: Module 5 - Setup VXLAN Cluster Mesh](module-5-setup-clustermesh.md)

[:arrow_left: Module 3.1 - Install Calico Enterprise](module-3.1-install-calient-mgmt.md)  
[:arrow_left: Module 3.2 - Setup clusters and connect to Calico Cloud](module-3.2-cc-setup.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
