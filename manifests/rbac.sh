#!/usr/bin/env bash

echo Creating a Calico Enterprise User called admin and its associated k8s Service Account
kubectl create sa admin -n default
kubectl create clusterrolebinding admin-access --clusterrole tigera-network-admin --serviceaccount default:admin
echo
echo Creating a token for the Service Account admin
kubectl create token admin --duration=24h

# Get the Kibana Login (Username is **elastic**)
export elasticToken=$(kubectl get -n tigera-elasticsearch secret tigera-secure-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
echo
echo The elasticsearch username is elastic and the token is: $elasticToken
