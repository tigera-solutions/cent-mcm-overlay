# Module 9.3 - Test Redis HA Demo App (Hipstershop)

## Creating a database failure scenario

Now we will takedown the local cluster database and service to simulate a database failure:

- In your ```redis-ha/setup.env``` variables file, set the ```TARGET_K8S_CONTEXTS``` variable to the K8s context name of the cluster that Hipstershop is installed in whose local database and REC we want to put into a failure/recovery state.
- Check for the local REAADB service endpoints:

  For example:

  ```bash
  kubectl get endpoints -n redis reaadb-testdb
  ```

  ```bash
  NAME                   ENDPOINTS                     AGE
  reaadb-testdb          172.17.106.203:11069          31h
  ```

- To takedown the local REC and database service, run the script: ```bash redis-ha/takedown-rec.sh```
- This will put the REC into a ```RecoveryReset``` state and rebuild the REC pods , and as a result takedown the database and accompanying local service and endpoints.
- Check the local REAADB endpoints and verify that there are none:
  
  For example:

  ```bash
  kubectl get endpoints -n redis reaadb-testdb
  ```

  ```bash
  NAME            ENDPOINTS   AGE
  reaadb-testdb   <none>      32h
  ```

- Now try to refresh the Hipstershop UI, this should fail and throw an 500 error that call to Redis timed out:
  
## Switch to Federated database service

- First check the endpoints of the federated REAADB service:
  
  For example:

  ```bash
  kubectl get endpoints -n redis reaadb-testdb-federated
  ```

  ```bash
  NAME                      ENDPOINTS             AGE
  reaadb-testdb-federated   172.16.27.222:11069   32h
  ```

  Notice that the federated REAADB service still contains the endpoint/s of the pods from the clusters where the REC and REAADB are in a good state.

- Change the ```cartservice``` Deployment to point to the federated REAADB service instead of the local service.
  
  For example:

  ```bash
  kubectl edit deployment -n cartservice cartservice
  ```

  Change the REDIS_ADDR to the REAADB federated service name, for example:

  ```yaml
  spec:
    containers:
    - env:
      - name: REDIS_ADDR
        value: reaadb-testdb-federated.redis:11069
  ```
  
  and write the changes to the file:

  ```bash
  deployment.apps/cartservice edited
  ```

- This will kick off a new ```checkoutservice``` pod with the new value, and refreshing the Hipstershop UI you will be able to see that the cart status is intact and able to run through the app flow again as it has recovered. This is because the federated service still populated the 'good' endpoints from remote clusters which the application is able to leverage without being aware that it is actually referencing a remote endpoint, thus proving the federated HA use-case for Redis.

## Recover REAADB from recovery mode

- Run the script: ```bash redis-ha/recover-db.sh```
- This should finish recovering all shards
- Check both the local and federated REAADB endpoints to ensure that all the endpoints are populated again:
  
  For example:

  ```bash
  kubectl get endpoints -n redis reaadb-testdb
  ```

  ```bash
  NAME            ENDPOINTS              AGE
  reaadb-testdb   172.17.106.216:11069   32h
  ```

  ```bash
  kubectl get endpoints -n redis reaadb-testdb-federated
  ```

  ```bash
  NAME                      ENDPOINTS                                  AGE
  reaadb-testdb-federated   172.16.27.222:11069,172.17.106.216:11069   32h
  ```

[:arrow_right: Module 10 - Cleanup](module-10-cleanup.md)  
[:arrow_left: Module 9.2 - Setup Redis HA Demo App (Hipstershop)](module-9.2-setup-redis-ha-demo-app.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
