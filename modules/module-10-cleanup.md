# Module 10 - Cleanup

## Overview

You can choose to either use the specific pieces below to only clean them up to reinstall or re-test those pieces in your cluster, or follow the cluster cleanup instructions to destroy all EKS/AWS/cluster resources.

## Uninstall Redis HA

- To uninstall all Redis resources in all clusters and associated services (local and federated) and reset back to a clean namespace, run the uninstall script: ```bash redis-ha/uninstall-redis.sh```

## Uninstall federated policies

- To remove all policies and tiers and allow all traffic in the cluster, delete the policies based on your cluster context:
  - ```kubectl delete -f federated-policy/cluster-1-policy```
  - ```kubectl delete -f federated-policy/cluster-2-policy```

## Uninstall Demo Apps

- Depending on cluster context, delete the namespaces and the default namespace ```nginx``` application:
  - ```kubectl delete -f demo-apps/01-namespaces.yaml```
  - ```kubectl delete -f demo-apps/02-namespaces.yaml```
  - ```kubectl delete -f demo-apps/40-nginx-deploy.yaml```
  - ```kubectl delete -f federated-svc/nginx-federated.yaml```
- This will also clean up any associated services of type ```LoadBalancer``` and the NLBs in AWS which is necessary before attempting to destroy the EKS clusters.

## Uninstall VXLAN Cluster Mesh

- To uninstall the cluster-mesh in the clusters and clean up associated secrets and objects, run the script: ```bash teardown-federation-overlay.sh```

## Cluster (and AWS resources cleanup)

- Clean up any remaining services of type ```LoadBalancer``` in all clusters (if they still exist after deleting Redis HA or the other apps) using ```kubectl delete svc -n <namespace> <svc-name>```
- Delete VPC peering connection/s:
  - Get the peering id:
  
    ```bash
    PEER_ID=$(aws ec2 describe-vpc-peering-connections --region <your-region-code> --query "VpcPeeringConnections[0].VpcPeeringConnectionId" --output text)
    ```

  - Delete the peering connection/s:

    ```bash
    aws ec2 delete-vpc-peering-connection --region <your-region-code> --vpc-peering-connection-id $PEER_ID
    ```

- Clean up the EKS clusters using eksctl:
  - Use ```eksctl get cluster --region=<your-region>``` to get the clusters that were spun up as part of this repo.
  - Then use ```eksctl delete cluster --region=<your-region>``` to delete the cluster. Repeat this for all clusters as needed.

[:arrow_left: Module 9.3 - Test Redis HA Demo App (Hipstershop)](module-9.3-test-redis-ha-demo-app.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
