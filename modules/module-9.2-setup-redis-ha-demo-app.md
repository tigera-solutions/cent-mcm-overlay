# Module 9.2 - Setup Redis HA Demo App (Hipstershop)

## Uninstall previous manifests

If the Hipstershop microservices demo application was installed in ```Module 6```, let's clean it up before creating the application manifests for this demo to save on compute resources.

Assuming you are in the right cluster context, run:

```bash
kubectl delete -f demo-apps/20-hipstershop-app.yaml
```

## Install Redis HA Hipstershop manifests

- Select one of the clusters to install the Hipstershop manifests to and switch to that K8s context
  
  For example:

  ```bash
  kubectl config get-contexts
  kubectl config use-context <context-name>
  ```

- Source the ```redis-ha/setup.env``` variables in order to substitute the ```REAADB_NAME``` local cluster database service into the manifest for the ```cartservice``` Deployment to point to.
  
  ```bash
  source redis-ha/setup.env
  ```

- Then substitute the values into the manifest and deploy onto the cluster

  ```bash
  sed -e "s?<REAADB_NAME>?$REAADB_NAME?g" \
    -e "s?<INSTALL_NAMESPACE>?$INSTALL_NAMESPACE?g" \
    -e "s?<REAADB_PORT>?$REAADB_PORT?g" \
    demo-apps/21-hipstershop-app-redisha.yaml | kubectl apply -f -
  ```

- Apply the network policies manifest for miorosegmentation between the different services and also to allow traffic to the Redis-deployed namespace by substituting the values into the manifest:
  
  ```bash
  sed -e "s?<INSTALL_NAMESPACE>?$INSTALL_NAMESPACE?g" \
    federated-policy/cluster-2-policy/05-msg-redisha.yaml | kubectl apply -f -
  ```

- Check that all the pods are up
  
  ```bash
  kubectl get pod -A -l zone=app2
  ```

  ```bash
  NAMESPACE               NAME                                     READY   STATUS    RESTARTS   AGE
  adservice               adservice-698ff9d8f8-88fhn               1/1     Running   0          4m50s
  cartservice             cartservice-7fc64f54d6-wf748             1/1     Running   0          4m51s
  checkoutservice         checkoutservice-6f799cb76f-phn5l         1/1     Running   0          4m52s
  currencyservice         currencyservice-79c4c96966-kbtrd         1/1     Running   0          4m51s
  emailservice            emailservice-6669f5bdbb-n5m85            1/1     Running   0          4m52s
  frontend                frontend-7c8d49d679-pvmkd                1/1     Running   0          4m52s
  loadgenerator           loadgenerator-648c7bc867-b65wm           1/1     Running   0          4m51s
  paymentservice          paymentservice-865bd6f586-2clx8          1/1     Running   0          4m51s
  productcatalogservice   productcatalogservice-5675dbc7d6-b488z   1/1     Running   0          4m51s
  recommendationservice   recommendationservice-5f4c4bd7c5-qkxpf   1/1     Running   0          4m52s
  shippingservice         shippingservice-5559f5655b-t2fjs         1/1     Running   0          4m51s
  ```  

- Check that the ```cartservice``` pod is using the local REAADB service:

  ```bash
  kubectl describe pods -n cartservice cartservice-7fc64f54d6-wf748 | grep REDIS_ADDR 
  ```

  ```bash
  REDIS_ADDR:  reaadb-testdb.redis:11069
  ```

- Check that the ```frontend-external``` ```LoadBalancer``` service got provisioned:
  
  ```bash
  kubectl get svc -n frontend frontend-external
  ```

  ```bash
  NAME                TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)        AGE
  frontend-external   LoadBalancer   172.21.149.62   a251g801ef5ah4mma8zq7d110ou3j215-4f05ea16f334e601.elb.us-east-1.amazonaws.com   80:30155/TCP   6m57s
  ```

- Check that you can access the Hipsterhop UI in a browser using the ```LoadBalancer``` svc URL

- Test the application flow:
  - Click on items
  - Add to Cart
  - Place Order

![hipstershop_usage](https://github.com/tigera-solutions/cent-mcm-overlay/assets/117195889/18d8e633-f8da-4ca5-aaeb-9b8bb0da1f6c)

[:arrow_right: Module 9.3 - Test Redis HA Demo App (Hipstershop)](module-9.3-test-redis-ha-demo-app.md)  
[:arrow_left: Module 9.1 - Setup Redis HA Database](module-9.1-setup-redis-ha-db.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
