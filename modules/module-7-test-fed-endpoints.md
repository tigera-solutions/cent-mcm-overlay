# Module 7 - Testing Federated Endpoint Policy

## Overview

In this demo, we will be enforcing the following network policy posture:

![zones_png](https://github.com/tigera-solutions/cent-mcm-overlay/assets/117195889/ac4f78dc-218d-4ee8-9b2e-26d44911fcca)

## Apply Policies

### Cluster-1

- On cluster-1, apply the policies:
  
  ```bash
  kubectl create -f federated-policy/cluster-1-policy
  ```

- Check the policy board and take note of the ```default-deny``` staged policy in the default tier.

- Once satisfied that the policy is not denying any legitimate traffic, enforce the ```default-deny``` policy and delete the staged policy by applying the commands below.

```bash
kubectl apply -f - <<-EOF   
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: default.default-deny
spec:
  tier: default
  order: 10000
  selector: zone == "app1"
  types:
  - Ingress
  - Egress
EOF
```

```bash
kubectl delete -f federated-policy/cluster-1-policy/01-default-deny.yaml
```

### Cluster-2

- On cluster-2, apply the policies:

  ```bash
  kubectl create -f federated-policy/cluster-2-policy
  ```

- Check the policy board and take note of the ```default-deny``` staged policy in the default tier.

- Once satisfied that the policy is not denying any legitimate traffic, enforce the ```default-deny``` policy and delete the staged policy by applying the commands below.

```bash
kubectl apply -f - <<-EOF   
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: default.default-deny
spec:
  tier: default
  order: 10000
  selector: zone == "app2" || zone == "shared"
  types:
  - Ingress
  - Egress
EOF
```

```bash
kubectl delete -f federated-policy/cluster-2-policy/01-default-deny.yaml
```

## Test Policies

- On cluster-2, get the IP of one of the nginx pods in the ```zone == shared``` set of workloads:
  
  ```bash
  kubectl get pod -A -l zone=shared -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"
  ```

- On cluster-1, exec into the shell of the ```client``` pod and try to hit the pod IP from the previous step:

  ```bash
  kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<dest-pod-IP>>:<port>'
  ```

  The response should return a HTTP 200 OK as the policy should allow the traffic.

- Look at the flow on the service graph in Calico Cloud to understand the flow log and to confirm the policies that were evaluated by Calico to allow the flow to the destination pod.

- On cluster-2, get the IP of one of the ```frontend``` pods in the ```zone == app2``` set of workloads:
  
  ```bash
  kubectl get pod -A -l zone=app2 -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels" | grep frontend
  ```

- On cluster-1, exec into the shell of the ```client``` pod and try to hit the pod IP from the previous step:

  ```bash
  kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<dest-pod-IP>>:<port>'
  ```

  This flow to the ```frontend``` pod IP should fail and timeout due to the policy denying flows to ```zone == app2```

- Look at the flow on the service graph in Calico Cloud to understand the flow log and to confirm the policies that were evaluated by Calico to deny the flow to the destination pod.

[:arrow_right: Module 8 - Testing Federated Services](module-8-test-fed-svc.md)  
[:arrow_left: Module 6 - Install Demo Apps](module-6-install-demo-apps.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
