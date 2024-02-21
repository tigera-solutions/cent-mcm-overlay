# Module 7 - Testing Federated Endpoint Policy

## Overview

In this demo, we will be enforcing the following network policy posture:

![zones_png](https://github.com/tigera-solutions/cent-mcm-overlay/assets/117195889/ac4f78dc-218d-4ee8-9b2e-26d44911fcca)

## Apply Policies

- On cluster-1, apply the policies:
  
  ```kubectl create -f federated-policy/cluster-1-policy```

- On cluster-2, apply the policies:

  ```kubectl create -f federated-policy/cluster-2-policy```

- Check the policy board and enforce the ```default-deny``` staged policy on both clusters.

## Test Policies

- On cluster-2, get the IP of one of the nginx pods in the ```zone == shared``` set of workloads:
  
  ```kubectl get pod -A -l zone=shared -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"```

- On cluster-1, exec into the shell of the ```client``` pod and try to hit the pod IP from the previous step:

  ```kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<dest-pod-IP>>:<port>'```

  The response should return a HTTP 200 OK as the policy should allow the traffic.

- Look at the flow on the service graph in Calico Cloud to understand the flow log and to confirm the policies that were evaluated by Calico to allow the flow to the destination pod.

- On cluster-2, get the IP of one of the ```frontend``` pods in the ```zone == app2``` set of workloads:
  
  ```kubectl get pod -A -l zone=app2 -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"```

- On cluster-1, exec into the shell of the ```client``` pod and try to hit the pod IP from the previous step:

  ```kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<dest-pod-IP>>:<port>'```

  This flow to the ```frontend``` pod IP should fail and timeout due to the policy denying flows to ```zone == app2```

- Look at the flow on the service graph in Calico Cloud to understand the flow log and to confirm the policies that were evaluated by Calico to deny the flow to the destination pod.

[:arrow_right: Module 8 - Testing Federated Services](module-8-test-fed-svc.md) <br>

[:leftwards_arrow_with_hook: Back to Main](../README.md)
