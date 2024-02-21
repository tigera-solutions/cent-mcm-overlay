# Module 1 - Getting Started

## Prerequisites

The following are the basic requirements to get going.

- AWS Account
- Git
- Terminal (bash, zsh)

## Local Environment Setup

### Steps

1. Ensure your environment has these tools:

   - AWS CLI upgrade to v2

     [Installation instructions](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

     Linux installation:

     ```bash
     curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
     unzip awscliv2.zip
     sudo ./aws/install
     . ~/.bashrc
     aws --version
     ```

   - eksctl

     [Installation instructions](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)

     Linux installation

     ```bash
     curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
     sudo mv /tmp/eksctl /usr/local/bin
     eksctl version
     ```

   - EKS kubectl

     [Installation instructions](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html)

     Linux installation:

     ```bash
     curl https://s3.us-west-2.amazonaws.com/amazon-eks/1.27.9/2024-01-04/bin/linux/amd64/kubectl -o /tmp/kubectl
     sudo chmod +x /tmp/kubectl
     sudo mv /tmp/kubectl /usr/local/bin
     kubectl version --short --client
     ```

   - git and Ncat

     [Installation instructions - git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
     [Installation instructions - Ncat](https://nmap.org/ncat/)
     Linux Amazon/Centos:

     ```bash
     sudo yum install git-all nc -y
     git --version
     nc --version
     ```

     >For convenience consider configuring [autocompletion for kubectl](https://kubernetes.io/docs/tasks/tools/included/optional-kubectl-configs-bash-linux/#enable-kubectl-autocompletion).

     ```bash
     # this is optional kubectl autocomplete configuration
     echo 'source <(kubectl completion bash)' >>~/.bashrc
     echo 'alias k=kubectl' >>~/.bashrc
     echo 'complete -o default -F __start_kubectl k' >>~/.bashrc
     source ~/.bashrc
     ```

   - K9s installation (optional)

     Download the k9s_Linux_x68_64.tar.gz file from the k9s github repo

     ```bash
     curl --silent --location "https://github.com/derailed/k9s/releases/download/v0.31.9/k9s_Linux_amd64.tar.gz" | tar xz -C /tmp
     sudo mv /tmp/k9s /usr/local/bin
     k9s version
     ```

2. Clone this repository

   ```bash
   git clone https://github.com/tigera-solutions/cent-mcm-overlay.git  && cd cent-mcm-overlay
   ```

[:arrow_right: Module 2 - Deploy the EKS Clusters](module-2-deploy-eks.md) <br>

[:leftwards_arrow_with_hook: Back to Main](../README.md)
