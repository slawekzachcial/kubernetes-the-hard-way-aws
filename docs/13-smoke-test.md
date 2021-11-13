# Smoke Test

## Data Encryption

Run commands from [Data Encryption
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#data-encryption)

Print a hexdump of the `kubernetes-the-hard-way` secret stored in etcd:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-0" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa \
  ubuntu@${external_ip} \
  "ETCDCTL_API=3 etcdctl get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C"
```

## Deployments

Run commands from [Deployments
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#deployments)

### Port Forwarding

Run commands from [Port Forwarding
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#port-forwarding)

### Logs

Run commands from [Logs
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#logs)

### Exec

Run commands from [Exec
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#exec)

## Services

Run commands from [Services
section](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md#services)

To create a firewall rule that allows remote access to the `nginx` node port:

```sh
NODE_PORT=$(kubectl get svc nginx \
  --output=jsonpath='{range .spec.ports[0]}{.nodePort}')

aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port ${NODE_PORT} \
  --cidr 0.0.0.0/0
```

To retrieve the external IP address of a worker instance:

```sh
EXTERNAL_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=worker-0" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
```

Next: [Cleaning Up](14-cleanup.md)
