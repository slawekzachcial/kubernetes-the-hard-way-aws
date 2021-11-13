# Generating Kubernetes Authentication Files for Authentication

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/05-kubernetes-configuration-files.md)

## Client Authentication Configs

### Kubernetes Public IP Address

```sh
KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LOAD_BALANCER_ARN} \
  --output text --query 'LoadBalancers[0].DNSName')
```

### The kubelet Kubernetes Configuration Files

```sh
mkdir -p cfg

for i in 0 1 2; do
  instance="worker-${i}"
  instance_hostname="ip-10-240-0-2${i}"
  bin/kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=tls/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=cfg/${instance}.kubeconfig

  bin/kubectl config set-credentials system:node:${instance_hostname} \
    --client-certificate=tls/${instance}.pem \
    --client-key=tls/${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=cfg/${instance}.kubeconfig

  bin/kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${instance_hostname} \
    --kubeconfig=cfg/${instance}.kubeconfig

  bin/kubectl config use-context default \
    --kubeconfig=cfg/${instance}.kubeconfig
done
```

### The kube-proxy Kubernetes Configuration File

```sh
bin/kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=cfg/kube-proxy.kubeconfig
bin/kubectl config set-credentials kube-proxy \
  --client-certificate=tls/kube-proxy.pem \
  --client-key=tls/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=cfg/kube-proxy.kubeconfig
bin/kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=kube-proxy \
  --kubeconfig=cfg/kube-proxy.kubeconfig
bin/kubectl config use-context default \
  --kubeconfig=cfg/kube-proxy.kubeconfig
```

### The kube-controller-manager Kubernetes Configuration File

```sh
bin/kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=cfg/kube-controller-manager.kubeconfig

bin/kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=tls/kube-controller-manager.pem \
  --client-key=tls/kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=cfg/kube-controller-manager.kubeconfig

bin/kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=cfg/kube-controller-manager.kubeconfig

bin/kubectl config use-context default --kubeconfig=cfg/kube-controller-manager.kubeconfig
```

### The kube-scheduler Kubernetes Configuration File

```sh
bin/kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=cfg/kube-scheduler.kubeconfig

bin/kubectl config set-credentials system:kube-scheduler \
  --client-certificate=tls/kube-scheduler.pem \
  --client-key=tls/kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=cfg/kube-scheduler.kubeconfig

bin/kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=cfg/kube-scheduler.kubeconfig

bin/kubectl config use-context default --kubeconfig=cfg/kube-scheduler.kubeconfig
```

### The admin Kubernetes Configuration File

```sh
bin/kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=cfg/admin.kubeconfig

bin/kubectl config set-credentials admin \
  --client-certificate=tls/admin.pem \
  --client-key=tls/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=cfg/admin.kubeconfig

bin/kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=cfg/admin.kubeconfig

bin/kubectl config use-context default --kubeconfig=cfg/admin.kubeconfig
```

## Distribute the Kubernetes Configuration Files

```sh
for instance in worker-0 worker-1 worker-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa \
    cfg/${instance}.kubeconfig cfg/kube-proxy.kubeconfig \
    ubuntu@${external_ip}:~/
done
```

```sh
for instance in controller-0 controller-1 controller-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa \
    cfg/admin.kubeconfig cfg/kube-controller-manager.kubeconfig cfg/kube-scheduler.kubeconfig \
    ubuntu@${external_ip}:~/
done
```

Next: [Generating the Data Encryption Config and Key](06-data-encryption-keys.md)
