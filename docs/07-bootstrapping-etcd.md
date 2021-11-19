# Bootstrapping the etcd Cluster

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/07-bootstrapping-etcd.md)

## Prerequisites

SSH to **each** controller in a separate terminal window.

controller-0:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-0" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

controller-1:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-1" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

controller-2:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-2" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

## Bootstrapping an etcd Cluster Member

### Download and Install the etcd Binaries

```sh
wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/v3.4.15/etcd-v3.4.15-linux-amd64.tar.gz"
```

```sh
{
  tar -xvf etcd-v3.4.15-linux-amd64.tar.gz
  sudo mv etcd-v3.4.15-linux-amd64/etcd* /usr/local/bin/
}
```

### Configure the etcd Server

```sh
{
  sudo mkdir -p /etc/etcd /var/lib/etcd
  sudo chmod 700 /var/lib/etcd
  sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
}
```

```sh
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
```

```sh
ETCD_NAME=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^name" | cut -d"=" -f2)

echo "${ETCD_NAME}"
```

```sh
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster controller-0=https://10.240.0.10:2380,controller-1=https://10.240.0.11:2380,controller-2=https://10.240.0.12:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Start the etcd Server

```sh
{
  sudo systemctl daemon-reload
  sudo systemctl enable etcd
  sudo systemctl start etcd
}
```

## Verification

```sh
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

Next: [Bootstrapping the Kubernetes Control Plane](08-bootstrapping-kubernetes-controllers.md)
