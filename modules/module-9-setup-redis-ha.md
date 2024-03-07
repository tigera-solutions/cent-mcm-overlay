# Module 9 - Setup Redis HA

The install bash script assumes you have the context names for each kubeconfig file and they're setup to be unique
  
```bash
bash redis-ha/install-rec.sh
```

- The State should be running and Spec Status Valid (will take a while to deploy the StatefulSets)
- Check this on all clusters

[Reference](https://docs.redis.com/latest/kubernetes/deployment/quick-start)