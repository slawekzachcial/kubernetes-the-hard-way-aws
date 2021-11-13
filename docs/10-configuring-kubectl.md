# Configuring kubectl for Remote Access

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/10-configuring-kubectl.md)

## The Admin Kubernetes Configuration File

```sh
bin/kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=tls/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443
bin/kubectl config set-credentials admin \
  --client-certificate=tls/admin.pem \
  --client-key=tls/admin-key.pem
bin/kubectl config set-context kubernetes-the-hard-way \
  --cluster=kubernetes-the-hard-way \
  --user=admin
bin/kubectl config use-context kubernetes-the-hard-way
```

## Verification

```sh
kubectl get componentstatuses
```

```sh
kubectl get nodes
```

Next: [Provisioning Pod Network Routes](docs/11-pod-network-routes.md)
