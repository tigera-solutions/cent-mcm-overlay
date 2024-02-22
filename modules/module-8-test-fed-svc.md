# Module 8 - Testing Federated Service

This demo scenario covers the use of [federated services](https://docs.tigera.io/calico-enterprise/latest/multicluster/federation/services-controller) to distribute application requests among the endpoints across different clusters.

## Configure Federated Service

The federated service uses `federation.tigera.io/serviceSelector` annotation to retrieve and aggregate endpoints from services that have the label key-pair specified in the annotation. This example uses `federation: "yes"` label to prepare local `default/nginx` service in each cluster.

Label `default/nginx` service in each cluster:

```bash
# run this command in cluster1 and cluster2
kubectl patch service nginx --patch-file federated-svc/nginx-service-patch.yaml
```

Deploy federated nginx service:

```bash
# if you want the federated nginx service in both clusters, then deploy it to both clusters
kubectl apply -f federated-svc/nginx-federated.yaml
```

Check endpoints for the local service and the federated service:

```bash
# list endpoints for local nginx service
kubectl get endpoints nginx

# list endpoints for the federated nginx service
kubectl get endpoints nginx-federated
```

>You should see that the local service only aggregates endpoints from the local cluster, but the federated service aggregates endpoints from both clusters.

Patch `default/nginx` deployment to have `zone=shared` label since the `client/client` pod only can egress to `zone=app1` and `zone=shared` endpoints.

```bash
# run this command in cluster1 and cluster2
kubectl patch deploy nginx --patch-file federated-svc/nginx-deploy-patch.yaml
```

## Test Federated Service

Open shell into a pod (e.g. `client` pod) and continuously query the federated service. Then try to scale endpoints behind the `default/nginx` deployment in each cluster and observe the IPs reported by querying the federated service.

```bash
# exec into the client pod in cluster1
kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash

# continuously query the federated service from within the client pod
while true; do curl -m2 http://nginx-federated.default; echo "";sleep 2; done

# scale nginx deployment in cluster2 to 2 replicas and observe returned IPs
kubectl scale deployment nginx --replicas=2

# scale nginx deployment in cluster1 to 0 replicas and observe returned IPs
kubectl scale deployment nginx --replicas=0
```

[:arrow_left: Module 7 - Test Federated Endpoint Policy](module-7-test-fed-endpoints.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
