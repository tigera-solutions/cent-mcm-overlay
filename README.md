# EKS Cluster mesh setup in Overlay/VXLAN mode on Calico Enterprise/Cloud

> :warning: **This repo is purely a work-in-progress(WIP) and is in active development. Other than contributors, anyone else should probably not try the stuff in this repo and expect it to work as is until it's finished and ready!**

## Overview

In this EKS-focused scenario, you will learn how to implement Calico Cluster Mesh in VXLAN/overlay mode in order to achieve policy federation across clusters as well as federate services across clusters to achieve high availability.

Calico Enterprise/Cloud federated endpoint identity and federated services are implemented in Kubernetes at the network layer. To apply fine-grained network policy between multiple clusters, the pod source and destination IPs must be preserved. Calico VXLAN/overlay cluster mesh is able to do so by using Calico CNI to federate clusters over a VXLAN overlay network setup between the participating clusters with minimal VPC/underlay configuration needed. There is no need to advertise pod and service CIDRs to the underlay/VPC network with this mode, and it makes configuration of the cluster mesh easier.

### Target Audience

- Cloud Professionals
- DevSecOps Professional
- Site Reliability Engineers (SRE)
- Solutions Architects
- Anyone interested in Calico Cloud :)

## Modules

This workshop is organized in sequential modules. One module will build up on top of the previous module, so please, follow the order as proposed below.

Module 1 - [Getting Started](modules/module-1-getting-started.md)  
Module 2 - [Deploy the EKS Clusters](modules/module-2-deploy-eks.md)  
Module 3 - [Install Calico Enterprise](modules/module-3.1-install-calient-mgmt.md) **or** [Install Calico Cloud](modules/module-3.2-cc-setup.md)  
Module 4 - [Setup VPC Peering](modules/module-4-setup-vpcpeering.md)  
Module 5 - [Setup VXLAN Cluster Mesh](modules/module-5-setup-clustermesh.md)  
Module 6 - [Install Demo Apps](modules/module-6-install-demo-apps.md)  
Module 7 - [Testing Federated Endpoint Policy](modules/module-7-test-fed-endpoints.md)  
Module 8 - [Testing Federated Service](modules/module-8-test-fed-svc.md)  
Module 9.1 - [Setup Redis HA Database](modules/module-9.1-setup-redis-ha-db.md)  
Module 9.2 - [Setup Redis HA Demo App (Hipstershop)](modules/module-9.2-setup-redis-ha-demo-app.md)  
Module 9.3 - [Test Redis HA Demo App (Hipstershop)](modules/module-9.3-test-redis-ha-demo-app.md)  
Module 10 - [Cleanup](modules/module-10-cleanup.md)

### Useful links

- [Project Calico](https://www.tigera.io/project-calico/)
- [Calico Academy - Get Calico Certified!](https://academy.tigera.io/)
- [O’REILLY EBOOK: Kubernetes security and observability](https://www.tigera.io/lp/kubernetes-security-and-observability-ebook)
- [Calico Users - Slack](https://slack.projectcalico.org/)

### Follow us on social media

- [LinkedIn](https://www.linkedin.com/company/tigera/)
- [Twitter](https://twitter.com/tigeraio)
- [YouTube](https://www.youtube.com/channel/UC8uN3yhpeBeerGNwDiQbcgw/)
- [Slack](https://calicousers.slack.com/)
- [Github](https://github.com/tigera-solutions/)
- [Discuss](https://discuss.projectcalico.tigera.io/)

> **Note**: The examples and sample code provided in this repo are intended to be consumed as instructional content. These will help you understand how Calico Cloud can be configured to build a functional solution. These examples are not intended for use in production environments.
