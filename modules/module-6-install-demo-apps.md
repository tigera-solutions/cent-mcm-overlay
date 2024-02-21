# Module 6 - Install Demo Apps

- Deploy the different application stacks on the clusters as below:
  
  Cluster-1:

  ```bash
  kubectl create -f demo-apps/01-namespaces.yaml
  kubectl create -f demo-apps/10-stars.yaml
  kubectl create -f demo-apps/40-nginx-deploy.yaml
  ```

  Cluster-2:

  ```bash
  kubectl create -f demo-apps/02-namespaces.yaml
  kubectl create -f demo-apps/20-hipstershop-app.yaml
  kubectl create -f demo-apps/30-dev-app.yaml
  kubectl create -f demo-apps/40-nginx-deploy.yaml
  ```

- The demo environment implements a zone-based architecture across the clusters with three major applications - stars,dev-nginx and hipstershop:

  Cluster-1:

  In cluster-1, we have the ```stars``` app pods labeled with ```zone=app1```
  Run the following command to see this:

  ```bash
  kubectl get pod -A -l zone=app1 -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"
  ```

  We should get all of the ```zone=app1``` pods across the namespaces:

  ```bash
  POD-NAME                         NAMESPACE       IP               POD-LABELS
  client-d668c86bf-sdc55           client          172.16.82.20     map[pod-template-hash:d668c86bf role:client zone:app1]
  management-ui-6795d4f59c-h2ncq   management-ui   172.16.163.158   map[pod-template-hash:6795d4f59c role:management-ui zone:app1]
  backend-8678866bb7-rxq6m         stars           172.16.163.156   map[pod-template-hash:8678866bb7 role:backend zone:app1]
  frontend-595f6d847-ss9v7         stars           172.16.163.157   map[pod-template-hash:595f6d847 role:frontend zone:app1]
  ```

  Cluster-2:

  In cluster-2, we have the ```dev``` pods labeled as ```zone=shared``` and the ```hipstershop``` app pods labeled as ```zone=app2```

  Run the following command to see all the pods labeled as ```zone=shared```

  ```bash
  kubectl get pod -A -l zone=shared -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"
  ```

  ```bash
  POD-NAME                     NAMESPACE   IP               POD-LABELS
  centos                       default     172.17.226.144   map[app:centos zone:shared]
  centos                       dev         172.17.64.19     map[app:centos zone:shared]
  dev-nginx-8564bf5476-2xpff   dev         172.17.64.20     map[app:nginx pod-template-hash:8564bf5476 security:strict zone:shared]
  dev-nginx-8564bf5476-kgbbp   dev         172.17.226.143   map[app:nginx pod-template-hash:8564bf5476 security:strict zone:shared]
  netshoot                     dev         172.17.64.21     map[app:netshoot zone:shared]
  ```

  Run the following command to see all the hipstershop app pods labeled as ```zone=app2```

  ```bash
  kubectl get pod -A -l zone=app2 -o custom-columns="POD-NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,POD-LABELS:.metadata.labels"
  ```

  ```bash
  POD-NAME                                 NAMESPACE               IP               POD-LABELS
  adservice-76488669b-jvtb7                adservice               172.17.226.142   map[app:adservice pod-template-hash:76488669b zone:app2]
  cartservice-86648449bb-fzr9h             cartservice             172.17.64.16     map[app:cartservice pod-template-hash:86648449bb zone:app2]
  checkoutservice-c9759c6cf-x9vxb          checkoutservice         172.17.64.11     map[app:checkoutservice pod-template-hash:c9759c6cf zone:app2]
  currencyservice-84b75b6b94-fn8mj         currencyservice         172.17.64.17     map[app:currencyservice pod-template-hash:84b75b6b94 zone:app2]
  emailservice-8666d6bbb6-dbbx6            emailservice            172.17.64.10     map[app:emailservice pod-template-hash:8666d6bbb6 zone:app2]
  frontend-6c6f577957-lzk9w                frontend                172.17.64.13     map[app:frontend pod-template-hash:6c6f577957 zone:app2]
  loadgenerator-8cdf78b5d-nd8h8            loadgenerator           172.17.64.23     map[app:loadgenerator pod-template-hash:8cdf78b5d zone:app2]
  paymentservice-5f8d6b68cd-bwz2b          paymentservice          172.17.64.14     map[app:paymentservice pod-template-hash:5f8d6b68cd zone:app2]
  productcatalogservice-58f5c6c474-b24dq   productcatalogservice   172.17.64.15     map[app:productcatalogservice pod-template-hash:58f5c6c474 zone:app2]
  recommendationservice-66df778ccc-7q59p   recommendationservice   172.17.64.12     map[app:recommendationservice pod-template-hash:66df778ccc zone:app2]
  redis-cart-7844cf686f-zs7vl              redis-cart              172.17.226.141   map[app:redis-cart pod-template-hash:7844cf686f zone:app2]
  shippingservice-8957d5b7b-wxsfg          shippingservice         172.17.64.18     map[app:shippingservice pod-template-hash:8957d5b7b zone:app2]
  ```

## Testing cross-cluster pod-to-pod communication

Here we will run some traffic flow tests by doing ```kubectl exec``` into pods

- Test traffic from the ```client``` pod in ```client``` namespace on cluster-1 to the ```frontend``` pod in cluster-2:
  
  - First, determine the IP of the ```frontend``` endpoint in cluster-2 by running the following command on cluster-2:

    ```bash
    kubectl get endpoints -n frontend frontend
    ```

    This should give an output similar to:

    ```bash
    NAME       ENDPOINTS           AGE
    frontend   172.17.64.13:8080   47h
    ```

    > :warning: **The endpoint IP will be different in your cluster, the above output is just an example**

  - Next, execute the ```curl``` command on the ```client``` pod in ```client``` namespace on cluster-1:
  
    > :warning: **Substitute the \<frontend-endpoint-ip\>:\<port\> with the value from your cluster from the previous command**

    ```bash
    kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<frontend-endpoint-ip>:<port>'
    ```

    You should get a successful response from the ```frontend``` pod in cluster-2 like so:

    ```bash
    HTTP/1.1 200 OK
    Set-Cookie: shop_session-id=38c6c7be-e731-4048-a070-c94fbc1253b4; Max-Age=172800
    Date: Thu, 30 Nov 2023 20:07:21 GMT
    Content-Type: text/html; charset=utf-8
    ```

- Test traffic from the ```client``` pod in ```client``` namespace on cluster-1 to one of the ```nginx``` pods in the ```dev``` namespace in cluster-2:

  - First, determine the IPs of the ```nginx-svc``` endpoints in cluster-2 by running the following command on cluster-2:

    ```bash
    kubectl get endpoints -n dev nginx-svc
    ```

    This should give an output similar to:

    ```bash
    NAME        ENDPOINTS                           AGE
    nginx-svc   172.17.226.143:80,172.17.64.20:80   2d
    ```

    > :warning: **The endpoint IP will be different in your cluster, the above output is just an example**

  - Next, execute the ```curl``` command on the ```client``` pod in ```client``` namespace on cluster-1 to one of the ```nginx-svc``` endpoints:

    ```bash
    kubectl -n client exec -it $(kubectl get po -n client -l role=client -ojsonpath='{.items[0].metadata.name}')  -- /bin/bash -c 'curl -m3 -I http://<nginx-svc-endpoint-ip>:<port>'
    ```

    You should get a successful response from the ```nginx-svc``` pod like so:

    ```bash
    HTTP/1.1 200 OK
    Server: nginx/1.25.3
    Date: Thu, 30 Nov 2023 20:43:34 GMT
    Content-Type: text/html
    Content-Length: 615
    Last-Modified: Tue, 24 Oct 2023 13:46:47 GMT
    Connection: keep-alive
    ETag: "6537cac7-267"
    Accept-Ranges: bytes
    ```

[:arrow_right: Module 7 - Testing Federated Endpoint Policy](module-7-test-fed-endpoints.md)  
[:arrow_left: Module 5 - Setup VXLAN Cluster Mesh](module-5-setup-clustermesh.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
