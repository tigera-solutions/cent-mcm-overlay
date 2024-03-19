# Module 9.1 - Setup Redis HA Database

## Overview

The goal here is to install Redis in an active-active configuration across multiple clusters. We will be using a trial (90 day) version of [Redis Enterprise for Kubernetes](https://docs.redis.com/latest/kubernetes/)

## Terminology

Redis Enterprise for Kubernetes uses an operator-based model of deployment (like Calico/tigera-operator) and some custom resource definitions to set everything up. These are explained below as they are used in the install config:

- REC (Redis Enterprise Cluster) - The base StatefulSet of Redis Enterprise pods of the deployment in a local cluster. In this deployment, we will have 3 replicas/pods with one pod on each worker node in every cluster.
- RERC (Redis Enterprise Remote Cluster) - The CR object that refers to a local or remote REC (depending on configuration) and required for setting up multi-cluster REC configuration.
- REAADB (Redis Enterprise Active-Active Database) - The CR object that refers to the actual active-active database that is created across the RECs in the multi-cluster setup. There can be multiple databases, but this example only creates one for demostrating the scenario.

## Installation

- Copy the example env variables file ```cp redis-ha/setup.env.example redis-ha/setup.env```
- Setup the variables in the ```setup.env``` as follows:
  - ```INSTALL_K8S_CONTEXTS``` is an array containing the K8s context names of all the clusters to install on, this assumes that the user's kubeconfig has the contexts that are being used for this setup. This can be seen by running ```kubectl config get-contexts```
  - ```REGION``` is an array containing the region of each EKS cluster deployed by the user. Ensure that if the clusters are in the same region, AZ is used instead to keep the values unique.
  - ```INSTALL_NAMESPACE``` is the namespace on all clusters that all resources will be created in
  - ```REC_NAMES``` is an array of RECs per cluster and can follow the same region naming to keep the naming consistent across clusters
  - ```RERC_NAMES``` is an array of RERCs per cluster and can follow the same region naming to keep the naming consistent across clusters
  - ```REAADB_NAME``` is the name of the active-active database to be created in all clusters. The database as well as accompanying federated services will get created with this name.The REAADB will be created with the same name in all clusters as per the design.
  - ```REAADB_PORT``` is the port of the ClusterIP of REAADB as well as the accompanying federated service. Can be left as default or changed as needed.
- Run the install script: ```bash redis-ha/install-redis.sh```
- The install script will switch contexts per cluster and setup all of the required installation along with the necessary Calico cluster-mesh federated services for database replication to happen cross-cluster.
- Once setup, either run ```bash redis-ha/check-redis.sh``` to check the status of all the resources or refer to the following commands to check everything:
  - ```kubectl get rec -n <INSTALL_NAMESPACE>``` to check the REC status. ```SPEC STATUS``` should be ```Valid``` and ```STATE``` should be ```Running```
  
    For example:

    ```bash
    NAME            NODES   VERSION    STATE     SPEC STATUS   LICENSE STATE   SHARDS LIMIT   LICENSE EXPIRATION DATE   AGE
    rec-cacentral   3       7.4.2-54   Running   Valid         Valid           4              2024-04-17T15:22:44Z      12h
    ```

  - ```kubectl get rerc -n <INSTALL_NAMESPACE>``` to check RERC status. Based on the cluster context, there should be a local RERC and remote RERCs. ```SPEC STATUS``` should be ```Valid``` and ```STATUS``` of all RERCs should be ```Active```
  
    For example:

    ```bash
    NAME             STATUS   SPEC STATUS   LOCAL
    rerc-cacentral   Active   Valid         true
    rerc-useast      Active   Valid         false
    ```

  - ```kubectl get reaadb -n <INSTALL_NAMESPACE>``` to REAADB status. The ```SPEC STATUS``` should be ```Valid```, ```STATUS``` should be ```active``` and ```REPLICATION STATUS``` should be ```up```

    For example:

    ```bash
    NAME            STATUS   SPEC STATUS   LINKED REDBS   REPLICATION STATUS
    reaadb-testdb   active   Valid                        up
    ```

  - All of the services can be checked with ```kubectl get svc -n <INSTALL_NAMESPACE>``` and endpoints with ```kubectl get endpoints -n <INSTALL_NAMESPACE>```
    - Check that the local ```REAADB_NAME``` service as well as the federated ```REAADB_NAME-federated``` services exist and have the necessary endpoints.

## Testing Database Replication across clusters

- Change context to the first cluster and bash into one of the local REC pods
  
  For example:

  ```bash
  kubectl exec -it rec-cacentral-0 -n redis -- /bin/bash
  ```

- Connect to the local REAADB ClusterIP service in the REC pod

  ```bash
  redislabs@rec-cacentral-0:/opt$ redis-cli -h reaadb-testdb -p 11069
  ```

- Write a couple of key:value entries into the database

  ```bash
  reaadb-testdb:11069> set Company "Tigera"
  OK
  reaadb-testdb:11069> set State "CA"
  OK
  ```

- Change context to another cluster and bash into one of the local REC pods

  For example:

  ```bash
  kubectl exec -it rec-useast-0 -n redis -- /bin/bash
  ```

- Connect to the local REAADB ClusterIP service in the REC pod

  ```bash
  redislabs@rec-useast-0:/opt$ redis-cli -h reaadb-testdb -p 11069
  ```

- Get the keys that were created in the first cluster, you should see the key:value entries got replicated to the second cluster's db

  ```bash
  reaadb-testdb:11069> get Company
  "Tigera"
  reaadb-testdb:11069> get State
  "CA"
  ```

This quick test validates that the database replication is working across the clusters and also validates that the federated service endpoints are working correctly. The next module uses the federated database service ```<REAADB_NAME>-federated" in the demo Google Hipstershop application to prove the Redis HA usecase.

[:arrow_right: Module 9.2 - Setup Redis HA Demo App (Hipstershop)](module-9.2-setup-redis-ha-demo-app.md)  
[:arrow_left: Module 8 - Testing Federated Service](module-8-test-fed-svc.md)  

[:leftwards_arrow_with_hook: Back to Main](../README.md)
