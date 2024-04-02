#!/bin/bash

NAMESPACE=redis

kubectl apply -f - << EOF
apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseDatabase
metadata:
  name: redis-enterprise-database
  namespace: $NAMESPACE
spec:
  evictionPolicy: illegal
EOF