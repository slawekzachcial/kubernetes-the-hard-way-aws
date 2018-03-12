# Provisioning Compute Resources

## Networking

https://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/vpc-subnets-commands-example.html

### VPC

```
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.240.0.0/24 \
  --output text --query 'Vpc.VpcId')
aws ec2 create-tags \
  --resources ${VPC_ID} \
  --tags Key=Name,Value=kubernetes-the-hard-way
aws ec2 modify-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --enable-dns-support '{"Value": true}'
aws ec2 modify-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --enable-dns-hostnames '{"Value": true}'
```

### DHCP Option Sets

```
AWS_REGION=us-east-2
```

```
DHCP_OPTION_SET_ID=$(aws ec2 create-dhcp-options \
  --dhcp-configuration \
    "Key=domain-name,Values=$AWS_REGION.compute.internal" \
    "Key=domain-name-servers,Values=AmazonProvidedDNS" \
  --output text --query 'DhcpOptions.DhcpOptionsId')
aws ec2 create-tags \
  --resources ${DHCP_OPTION_SET_ID} \
  --tags Key=Name,Value=kubernetes
aws ec2 associate-dhcp-options \
  --dhcp-options-id ${DHCP_OPTION_SET_ID} \
  --vpc-id ${VPC_ID}
```

### Subnet

```
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block 10.240.0.0/24 \
  --output text --query 'Subnet.SubnetId')
aws ec2 create-tags \
  --resources ${SUBNET_ID} \
  --tags Key=Name,Value=kubernetes
```

### Internet Gateway

```
INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway \
  --output text --query 'InternetGateway.InternetGatewayId')
aws ec2 create-tags \
  --resources ${INTERNET_GATEWAY_ID} \
  --tags Key=Name,Value=kubernetes
aws ec2 attach-internet-gateway \
  --internet-gateway-id ${INTERNET_GATEWAY_ID} \
  --vpc-id ${VPC_ID}
```

### Route Tables

```
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} \
  --output text --query 'RouteTable.RouteTableId')
aws ec2 create-tags \
  --resources ${ROUTE_TABLE_ID} \
  --tags Key=Name,Value=kubernetes
aws ec2 associate-route-table \
  --route-table-id ${ROUTE_TABLE_ID} \
  --subnet-id ${SUBNET_ID}
aws ec2 create-route \
  --route-table-id ${ROUTE_TABLE_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${INTERNET_GATEWAY_ID}
```

### Firewall Rules (aka Security Groups)

https://docs.aws.amazon.com/cli/latest/userguide/cli-ec2-sg.html

```
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name kubernetes \
  --description "Kubernetes security group" \
  --vpc-id ${VPC_ID} \
  --output text --query 'GroupId')
aws ec2 create-tags \
  --resources ${SECURITY_GROUP_ID} \
  --tags Key=Name,Value=kubernetes
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol all \
  --cidr 10.240.0.0/24
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol all \
  --cidr 10.200.0.0/16
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 6443 \
  --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol icmp \
  --port -1 \
  --cidr 0.0.0.0/0
```

TODO: Is `authorize-security-group-ingress … --source-group …` needed?

### Kubernetes Public Address

```
LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer \
  --name kubernetes \
  --subnets ${SUBNET_ID} \
  --scheme internet-facing \
  --type network \
  --output text --query 'LoadBalancers[].LoadBalancerArn')
KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LOAD_BALANCER_ARN} \
  --output text --query 'LoadBalancers[].DNSName')
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
  --name kubernetes \
  --protocol TCP \
  --port 6443 \
  --vpc-id ${VPC_ID} \
  --target-type ip \
  --output text --query 'TargetGroups[].TargetGroupArn')
aws elbv2 register-targets \
  --target-group-arn ${TARGET_GROUP_ARN} \
  --targets Id=10.240.0.1{0,1,2}
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn ${LOAD_BALANCER_ARN} \
  --protocol TCP \
  --port 6443 \
  --default-actions Type=forward,TargetGroupArn=${TARGET_GROUP_ARN} \
  --output text --query 'Listeners[].ListenerArn')
```

## Compute Instances

### Instance Image

```
IMAGE_ID=$(aws ec2 describe-images --owners 099720109477 \
  --filters \
  'Name=root-device-type,Values=ebs' \
  'Name=architecture,Values=x86_64' \
  'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*' \
  | jq -r '.Images|sort_by(.Name)[-1]|.ImageId')
```

### SSH Key Pair

```
mkdir -p ssh
aws ec2 create-key-pair \
  --key-name kubernetes \
  --output text --query 'KeyMaterial' \
  > ssh/kubernetes.id_rsa
chmod 600 ssh/kubernetes.id_rsa
```

### Kubernetes Controllers

Using `t2.micro` instead of `t2.small` as the former is covered by free tier

```
for i in 0 1 2; do
  instance_id=$(aws ec2 run-instances \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t2.micro \
    --private-ip-address 10.240.0.1${i} \
    --user-data "name=controller-${i}" \
    --subnet-id ${SUBNET_ID} \
    --output text --query 'Instances[].InstanceId')
  aws ec2 modify-instance-attribute \
    --instance-id ${instance_id} \
    --no-source-dest-check
  aws ec2 create-tags \
    --resources ${instance_id} \
    --tags "Key=Name,Value=controller-${i}"
done
```

### Kubernetes Workers

```
for i in 0 1 2; do
  instance_id=$(aws ec2 run-instances \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t2.micro \
    --private-ip-address 10.240.0.2${i} \
    --user-data "name=worker-${i}|pod-cidr=10.200.${i}.0/24" \
    --subnet-id ${SUBNET_ID} \
    --output text --query 'Instances[].InstanceId')
  aws ec2 modify-instance-attribute \
    --instance-id ${instance_id} \
    --no-source-dest-check
  aws ec2 create-tags \
    --resources ${instance_id} \
    --tags "Key=Name,Value=worker-${i}"
done
```


# Provisioning a CA and Generating TLS Certificates

**IMPORTANT**:
subject alternative names don't work properly using openssl and commands below

## Certificate Authority

```
mkdir tls
```

<!--
```
mkdir -p tls
openssl genrsa \
  -out tls/ca-key.pem 2048
openssl req -new -x509 \
  -key tls/ca-key.pem -out tls/ca.pem \
  -subj '/C=US/ST=Oregon/L=Portland/O=Kubernetes/OU=CA/CN=Kubernetes'
```
-->

```
cat > tls/ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > tls/ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert -initca tls/ca-csr.json | cfssljson -bare tls/ca
```

## Client and Server Certificates

### Admin Client Certificate

<!--
```
openssl genrsa \
  -out tls/admin-key.pem 2048
openssl req -new \
  -key tls/admin-key.pem -out tls/admin.csr \
  -subj '/C=US/ST=Oregon/L=Portland/O=system:masters/OU=Kubernetes The Hard Way/CN=admin'
openssl x509 -req \
  -in tls/admin.csr -out tls/admin.pem \
  -CA tls/ca.pem -CAkey tls/ca-key.pem -CAcreateserial
```
-->

```
cat > tls/admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=tls/ca.pem \
  -ca-key=tls/ca-key.pem \
  -config=tls/ca-config.json \
  -profile=kubernetes \
  tls/admin-csr.json | cfssljson -bare tls/admin
```

### Kubelet Client Certificates

<!--
```
for instance in worker-0 worker-1 worker-2; do
  openssl req -nodes \
    -newkey rsa:2048 -keyout tls/${instance}-key.pem -out tls/${instance}.csr \
    -subj "/C=US/ST=Oregon/L=Portland/O=system:nodes/OU=Kubernetes The Hard Way/CN=system:node:${instance}"

  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')

  internal_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PrivateIpAddress')

  cat > tls/${instance}.extensions.cnf <<EOF
basicConstraints=CA:FALSE
subjectAltName=@my_subject_alt_names
subjectKeyIdentifier = hash

[ my_subject_alt_names ]
DNS.1 = ${instance}
DNS.2 = ${external_ip}
DNS.3 = ${internal_ip}
EOF

  openssl x509 -req \
    -in tls/${instance}.csr -out tls/${instance}.pem \
    -extfile tls/${instance}.extensions.cnf \
    -CA tls/ca.pem -CAkey tls/ca-key.pem -CAcreateserial
done
```
-->

```
for i in 0 1 2; do
  instance="worker-${i}"
  instance_hostname="ip-10-240-0-2${i}"
  cat > tls/${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance_hostname}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')

  internal_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PrivateIpAddress')

  cfssl gencert \
    -ca=tls/ca.pem \
    -ca-key=tls/ca-key.pem \
    -config=tls/ca-config.json \
    -hostname=${instance_hostname},${external_ip},${internal_ip} \
    -profile=kubernetes \
    tls/worker-${i}-csr.json | cfssljson -bare tls/worker-${i}
done
```

### kube-proxy Client Certificate

<!--
```
openssl genrsa \
  -out tls/kube-proxy-key.pem 2048
openssl req -new \
  -key tls/kube-proxy-key.pem -out tls/kube-proxy.csr \
  -subj '/C=US/ST=Oregon/L=Portland/O=system:node-proxier/OU=Kubernetes The Hard Way/CN=system:kube-proxy'
openssl x509 -req \
  -in tls/kube-proxy.csr -out tls/kube-proxy.pem \
  -CA tls/ca.pem -CAkey tls/ca-key.pem -CAcreateserial
```
-->

```
cat > tls/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=tls/ca.pem \
  -ca-key=tls/ca-key.pem \
  -config=tls/ca-config.json \
  -profile=kubernetes \
  tls/kube-proxy-csr.json | cfssljson -bare tls/kube-proxy
```

### Kubernetes API Server Certificate

```
KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LOAD_BALANCER_ARN} \
  --output text --query 'LoadBalancers[0].DNSName')
```

<!--
```
openssl genrsa \
  -out tls/kubernetes-key.pem 2048
openssl req -new \
  -key tls/kubernetes-key.pem -out tls/kubernetes.csr \
  -subj '/C=US/ST=Oregon/L=Portland/O=Kubernetes/OU=Kubernetes The Hard Way/CN=kubernetes'

cat > tls/kubernetes.extensions.cnf <<EOF
basicConstraints=CA:FALSE
subjectAltName=@my_subject_alt_names
subjectKeyIdentifier = hash

[ my_subject_alt_names ]
DNS.1 = 10.32.0.1
DNS.2 = 10.240.0.10
DNS.3 = 10.240.0.11
DNS.4 = 10.240.0.12
DNS.5 = ${KUBERNETES_PUBLIC_ADDRESS}
DNS.6 = 127.0.0.1
DNS.7 = kubernetes.default
EOF

openssl x509 -req \
  -in tls/kubernetes.csr -out tls/kubernetes.pem \
  -extfile tls/kubernetes.extensions.cnf \
  -CA tls/ca.pem -CAkey tls/ca-key.pem -CAcreateserial
```
-->

```
cat > tls/kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=tls/ca.pem \
  -ca-key=tls/ca-key.pem \
  -config=tls/ca-config.json \
  -hostname=10.32.0.1,10.240.0.10,10.240.0.11,10.240.0.12,ip-10-240-0-10,ip-10-240-0-11,ip-10-240-0-12,${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  tls/kubernetes-csr.json | cfssljson -bare tls/kubernetes
```

<!--
NOT NEEDED - using Network Loadbalancer
Import certificate and use it in load balancer

```
CERTIFICATE_ARN=$(aws acm import-certificate \
  --certificate file://tls/kubernetes.pem \
  --private-key file://tls/kubernetes-key.pem)
aws elbv2 modify-listener \
  --listener-arn ${LISTENER_ARN} \
  --certificates "CertificateArn=${CERTIFICATE_ARN}"
```
-->

## Distribute the Client and Server Certificates

```
for instance in worker-0 worker-1 worker-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa \
    tls/ca.pem tls/${instance}-key.pem tls/${instance}.pem \
    ubuntu@${external_ip}:~/
done
```

```
for instance in controller-0 controller-1 controller-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa \
    tls/ca.pem tls/ca-key.pem tls/kubernetes-key.pem tls/kubernetes.pem \
    ubuntu@${external_ip}:~/
done
```

# Generating Kubernetes Authentication Files for Authentication

## Client Authentication Configs

### Kubernetes Public IP Address

```
KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LOAD_BALANCER_ARN} \
  --output text --query 'LoadBalancers[0].DNSName')
```

### The kubelet Kubernetes Configuration Files

```
mkdir -i cfg

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

```
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

## Distribute the Kubernetes Configuration Files

```
for instance in worker-0 worker-1 worker-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa \
    cfg/${instance}.kubeconfig cfg/kube-proxy.kubeconfig \
    ubuntu@${external_ip}:~/
done
```

# Generating the Data Encryption Config and Key

## The Encryption Key

```
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
```

## The Encryption Config File

```
cat > cfg/encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
```

```
for instance in controller-0 controller-1 controller-2; do
  external_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].PublicIpAddress')
  scp -i ssh/kubernetes.id_rsa cfg/encryption-config.yaml ubuntu@${external_ip}:~/
done
```

# Bootstrapping the etcd Cluster

SSH to controller-0, controller-1, controller-2:

```
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-N" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

On each controller:

```
wget -q --show-progress --https-only --timestamping \
  "https://github.com/coreos/etcd/releases/download/v3.2.11/etcd-v3.2.11-linux-amd64.tar.gz"
tar -xvf etcd-v3.2.11-linux-amd64.tar.gz
sudo mv etcd-v3.2.11-linux-amd64/etcd* /usr/local/bin/
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
```

etcd member unique name must be set manually as AWS uses a different hostname:

```
ETCD_NAME=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^name" | cut -d"=" -f2)
echo "${ETCD_NAME}"
```

```
cat > etcd.service <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
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
  --listen-client-urls https://${INTERNAL_IP}:2379,http://127.0.0.1:2379 \\
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

sudo mv etcd.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
ETCDCTL_API=3 etcdctl member list
```

# Bootstrapping the Kubernetes Control Plane

SSH to controller-0, controller-1, controller-2:

```
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-N" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

On each controller:

```
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubectl"
chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
sudo mkdir -p /var/lib/kubernetes/
sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem encryption-config.yaml /var/lib/kubernetes/
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

cat > kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --admission-control=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --insecure-bind-address=127.0.0.1 \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-ca-file=/var/lib/kubernetes/ca.pem \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --leader-elect=true \\
  --master=http://127.0.0.1:8080 \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --leader-elect=true \\
  --master=http://127.0.0.1:8080 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-apiserver.service kube-scheduler.service kube-controller-manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
```

```
kubectl get componentstatuses
```

## RBAC for Kubelet Authorization

SSH to controller-0:
```
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-0" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

```
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF
```

## The Kubernetes Frontend Load Balancer

Nothing to do - already setup in previous section

# Bootstrapping the Kubernetes Worker Nodes

SSH to worker-0, worker-1, worker-2:

```
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=worker-N" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa ubuntu@${external_ip}
```

On each worker:

```
sudo apt-get update
sudo apt-get -y install socat
wget -q --show-progress --https-only --timestamping \
  https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz \
  https://github.com/containerd/cri-containerd/releases/download/v1.0.0-beta.1/cri-containerd-1.0.0-beta.1.linux-amd64.tar.gz \
  https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kube-proxy \
  https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubelet
sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes
sudo tar -xvf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin/
sudo tar -xvf cri-containerd-1.0.0-beta.1.linux-amd64.tar.gz -C /
chmod +x kubectl kube-proxy kubelet
sudo mv kubectl kube-proxy kubelet /usr/local/bin/

POD_CIDR=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^pod-cidr" | cut -d"=" -f2)
echo "${POD_CIDR}"

cat > 10-bridge.conf <<EOF
{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

cat > 99-loopback.conf <<EOF
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
EOF

sudo mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/

WORKER_NAME=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^name" | cut -d"=" -f2)
echo "${WORKER_NAME}"

sudo mv ${WORKER_NAME}-key.pem ${WORKER_NAME}.pem /var/lib/kubelet/
sudo mv ${WORKER_NAME}.kubeconfig /var/lib/kubelet/kubeconfig
sudo mv ca.pem /var/lib/kubernetes/

cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=cri-containerd.service
Requires=cri-containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --allow-privileged=true \\
  --anonymous-auth=false \\
  --authorization-mode=Webhook \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --cloud-provider= \\
  --cluster-dns=10.32.0.10 \\
  --cluster-domain=cluster.local \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/cri-containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --pod-cidr=${POD_CIDR} \\
  --register-node=true \\
  --runtime-request-timeout=15m \\
  --tls-cert-file=/var/lib/kubelet/${WORKER_NAME}.pem \\
  --tls-private-key-file=/var/lib/kubelet/${WORKER_NAME}-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --cluster-cidr=10.200.0.0/16 \\
  --kubeconfig=/var/lib/kube-proxy/kubeconfig \\
  --proxy-mode=iptables \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kubelet.service kube-proxy.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable containerd cri-containerd kubelet kube-proxy
sudo systemctl start containerd cri-containerd kubelet kube-proxy
```

# Configuring kubectl for Remote Access

```
KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LOAD_BALANCER_ARN} \
  --output text --query 'LoadBalancers[0].DNSName')
```

kubeconfig file suitable to authenticate as `admin` user:

```
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

# Provisioning Pod Network Routes

## The Routing Table

```
for instance in worker-0 worker-1 worker-2; do
  instance_id_ip="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress]')"
  instance_id="$(echo "${instance_id_ip}" | cut -f1)"
  instance_ip="$(echo "${instance_id_ip}" | cut -f2)"
  pod_cidr="$(aws ec2 describe-instance-attribute \
    --instance-id "${instance_id}" \
    --attribute userData \
    --output text --query 'UserData.Value' \
    | base64 --decode | tr "|" "\n" | grep "^pod-cidr" | cut -d'=' -f2)"
  echo "${instance_ip} ${pod_cidr}"

  aws ec2 create-route \
    --route-table-id "${ROUTE_TABLE_ID}" \
    --destination-cidr-block "${pod_cidr}" \
    --instance-id "${instance_id}"
done
```

## Routes

The last command above (`aws ec2 create-route`) creates the route for each
worker.

```
aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --query 'RouteTables[].Routes'
```

# Deploying the DNS Cluster Add-on

Same commands as on
https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/12-dns-addon.md

# Smoke Test

## Data Encryption

Print a hexdump of the `kubernetes-the-hard-way` secret stored in etcd:

```
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-0" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
ssh -i ssh/kubernetes.id_rsa \
  ubuntu@${external_ip} \
  "ETCDCTL_API=3 etcdctl get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C"
```

## Create the Node Port Firewall Rule

```
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port ${NODE_PORT} \
  --cidr 0.0.0.0/0
```

Grab the `EXTERNAL_IP` for one of the worker nodes to test nginx service

```
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=worker-0" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')
```

# Cleaning Up

## Compute Instances

```
aws ec2 terminate-instances \
  --instance-ids \
    $(aws ec2 describe-instances \
      --filter "Name=tag:Name,Values=controller-0,controller-1,controller-2,worker-0,worker-1,worker-2" \
      --output text --query 'Reservations[].Instances[].InstanceId')
aws ec2 delete-key-pair \
  --key-name kubernetes
```

## Networking

```
aws elbv2 delete-load-balancer \
  --load-balancer-arn "${LOAD_BALANCER_ARN}"
aws elbv2 delete-target-group \
  --target-group-arn "${TARGET_GROUP_ARN}"
aws ec2 delete-security-group \
  --group-id "${SECURITY_GROUP_ID}"
ROUTE_TABLE_ASSOCIATION_ID="$(aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --output text --query 'RouteTables[].Associations[].RouteTableAssociationId')"
aws ec2 disassociate-route-table \
  --association-id "${ROUTE_TABLE_ASSOCIATION_ID}"
# aws ec2 delete-route \
#   --route-table-id "${ROUTE_TABLE_ID}" \
#   --destination-cidr-block 0.0.0.0/0
# aws ec2 delete-route \
#   --route-table-id "${ROUTE_TABLE_ID}" \
#   --destination-cidr-block 10.200.0.0/24
# aws ec2 delete-route \
#   --route-table-id "${ROUTE_TABLE_ID}" \
#   --destination-cidr-block 10.200.1.0/24
# aws ec2 delete-route \
#   --route-table-id "${ROUTE_TABLE_ID}" \
#   --destination-cidr-block 10.200.2.0/24
aws ec2 delete-route-table \
  --route-table-id "${ROUTE_TABLE_ID}"
aws ec2 detach-internet-gateway \
  --internet-gateway-id "${INTERNET_GATEWAY_ID}" \
  --vpc-id "${VPC_ID}"
aws ec2 delete-internet-gateway \
  --internet-gateway-id "${INTERNET_GATEWAY_ID}"
aws ec2 delete-subnet \
  --subnet-id "${SUBNET_ID}"
aws ec2 delete-dhcp-options \
  --dhcp-options-id "${DHCP_OPTION_SET_ID}"
aws ec2 delete-vpc \
  --vpc-id "${VPC_ID}"
```

