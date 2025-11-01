# Kubernetes The Hard Way - AWS

Welcome to the AWS companion to [Kubernetes The Hard
Way](https://github.com/kelseyhightower/kubernetes-the-hard-way/) guide.

It compiles AWS CLI commands, based initially on revision
[8185017](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/818501707e418fc4d6e6aedef8395ca368e3097e)
of the guide (right before AWS support has been removed). This page contains
the same sections so that it is easy to follow it side-by-side with the original
guide. It contains `aws` commands that correspond to `gcloud` commands. It also
highlights differences from the original guide.

The intent of this page is similar to the original guide. My motivation to
create it has been to learn more about AWS and Kubernetes.

This revision of the guide corresponds to revision [79a3f79](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/79a3f79b27bd28f82f071bb877a266c2e62ee506)
of the original guide which provides details about setting up **Kubernetes 1.21**.

## Labs

* [Prerequisites](#prerequisites)
* [Installing the Client Tools](#installing-the-client-tools)
* [Provisioning Compute Resources](#provisioning-compute-resources)
* [Provisioning a CA and Generating TLS Certificates](#provisioning-a-ca-and-generating-tls-certificates)
* [Generating Kubernetes Configuration Files for Authentication](#generating-kubernetes-configuration-files-for-authentication)
* [Generating the Data Encryption Config and Key](#generating-the-data-encryption-config-and-key)
* [Bootstrapping the etcd Cluster](#bootstrapping-the-etcd-cluster)
* [Bootstrapping the Kubernetes Control Plane](#bootstrapping-the-kubernetes-control-plane)
* [Bootstrapping the Kubernetes Worker Nodes](#bootstrapping-the-kubernetes-worker-nodes)
* [Configuring kubectl for Remote Access](#configuring-kubectl-for-remote-access)
* [Provisioning Pod Network Routes](#provisioning-pod-network-routes)
* [Deploying the DNS Cluster Add-on](#deploying-the-dns-cluster-add-on)
* [Smoke Test](#smoke-test)
* [Cleaning Up](#cleaning-up)

## Prerequisites

### Amazon Web Services

The commands below deploy Kubernetes cluster into [Amazon Web
Services](https://aws.amazon.com). At some point I was able to provision AWS
resources within [AWS Free Tier](https://aws.amazon.com/free/), at no cost.
However, as the page evolves I am not able to validate it each time so some
minimum charges may apply.

### Amazon Web Services CLI

Install AWS CLI following instructions at <https://aws.amazon.com/cli/>.

Details how to configure AWS CLI are available in
[this guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html).

## Installing the Client Tools

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/02-client-tools.md).

## Provisioning Compute Resources

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/03-compute-resources.md)

### Networking

#### Virtual Private Cloud Network

Create VPC:

```sh
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.240.0.0/24 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=kubernetes-the-hard-way}]' \
  --output text --query 'Vpc.VpcId')

aws ec2 modify-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --enable-dns-support '{"Value": true}'

aws ec2 modify-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --enable-dns-hostnames '{"Value": true}'
```

Create Subnet:

```sh
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block 10.240.0.0/24 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=kubernetes-the-hard-way}]' \
  --output text --query 'Subnet.SubnetId')
```

Create Internet Gateway:

```sh
INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=kubernetes-the-hard-way}]' \
  --output text --query 'InternetGateway.InternetGatewayId')

aws ec2 attach-internet-gateway \
  --internet-gateway-id ${INTERNET_GATEWAY_ID} \
  --vpc-id ${VPC_ID}
```

Create Route Table:

```sh
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=kubernetes-the-hard-way}]' \
  --output text --query 'RouteTable.RouteTableId')

aws ec2 associate-route-table \
  --route-table-id ${ROUTE_TABLE_ID} \
  --subnet-id ${SUBNET_ID}

aws ec2 create-route \
  --route-table-id ${ROUTE_TABLE_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${INTERNET_GATEWAY_ID}
```

#### Firewall Rules (aka Security Group)

```sh
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name kubernetes-the-hard-way \
  --description "Kubernetes The Hard Way security group" \
  --vpc-id ${VPC_ID} \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=kubernetes-the-hard-way}]' \
  --output text --query 'GroupId')

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

List the created security group rules:

```sh
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=${SECURITY_GROUP_ID}" \
  --query 'sort_by(SecurityGroupRules, &CidrIpv4)[].{a_Protocol:IpProtocol,b_FromPort:FromPort,c_ToPort:ToPort,d_Cidr:CidrIpv4}' \
  --output table
```

Output:

```txt
-----------------------------------------------------------
|               DescribeSecurityGroupRules                |
+------------+-------------+-----------+------------------+
| a_Protocol | b_FromPort  | c_ToPort  |     d_Cidr       |
+------------+-------------+-----------+------------------+
|  -1        |  -1         |  -1       |  0.0.0.0/0       |
|  tcp       |  6443       |  6443     |  0.0.0.0/0       |
|  tcp       |  22         |  22       |  0.0.0.0/0       |
|  icmp      |  -1         |  -1       |  0.0.0.0/0       |
|  -1        |  -1         |  -1       |  10.200.0.0/16   |
|  -1        |  -1         |  -1       |  10.240.0.0/24   |
+------------+-------------+-----------+------------------+
```

#### Kubernetes Public IP Address

```sh
ALLOCATION_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=kubernetes-the-hard-way}]' \
  --output text --query 'AllocationId')
```

Verify the address was created in your default region:

```sh
aws ec2 describe-addresses --allocation-ids ${ALLOCATION_ID}
```

### Compute Instances

Create SSH key pair:

```sh
aws ec2 create-key-pair \
  --key-name kubernetes-the-hard-way \
  --output text --query 'KeyMaterial' \
  > kubernetes-the-hard-way.id_rsa

chmod 600 kubernetes-the-hard-way.id_rsa
```

Find instance image ID:

```sh
IMAGE_ID=$(aws ec2 describe-images --owners 099720109477 \
  --filters \
  'Name=root-device-type,Values=ebs' \
  'Name=architecture,Values=x86_64' \
  'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*' \
  --output text --query 'sort_by(Images[],&Name)[-1].ImageId')

echo ${IMAGE_ID}
```

#### Kubernetes Controllers

Using `t2.micro` instead of `t2.small` as `t2.micro` is covered by AWS free tier.

```sh
for i in 0 1 2; do
  instance_id=$(aws ec2 run-instances \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes-the-hard-way \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t2.micro \
    --private-ip-address 10.240.0.1${i} \
    --user-data "name=controller-${i}" \
    --subnet-id ${SUBNET_ID} \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=controller-${i}}]" \
    --output text --query 'Instances[].InstanceId')

  aws ec2 modify-instance-attribute \
    --instance-id ${instance_id} \
    --no-source-dest-check
done
```

#### Kubernetes Workers

```sh
for i in 0 1 2; do
  instance_id=$(aws ec2 run-instances \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes-the-hard-way \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t2.micro \
    --private-ip-address 10.240.0.2${i} \
    --user-data "name=worker-${i}|pod-cidr=10.200.${i}.0/24" \
    --subnet-id ${SUBNET_ID} \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=worker-${i}}]" \
    --output text --query 'Instances[].InstanceId')

  aws ec2 modify-instance-attribute \
    --instance-id ${instance_id} \
    --no-source-dest-check
done
```

#### Verification

List the compute instances in your default region:

```sh
aws ec2 describe-instances \
  --filters Name=vpc-id,Values=${VPC_ID} \
  --query 'sort_by(Reservations[].Instances[],&PrivateIpAddress)[].{d_INTERNAL_IP:PrivateIpAddress,e_EXTERNAL_IP:PublicIpAddress,a_NAME:Tags[?Key==`Name`].Value | [0],b_ZONE:Placement.AvailabilityZone,c_MACHINE_TYPE:InstanceType,f_STATUS:State.Name}' \
  --output table
```

Output:

```txt
-------------------------------------------------------------------------------------------------
|                                       DescribeInstances                                       |
+--------------+-------------+-----------------+----------------+------------------+------------+
|    a_NAME    |   b_ZONE    | c_MACHINE_TYPE  | d_INTERNAL_IP  |  e_EXTERNAL_IP   | f_STATUS   |
+--------------+-------------+-----------------+----------------+------------------+------------+
|  controller-0|  us-east-2a |  t2.micro       |  10.240.0.10   |  XX.XXX.XXX.XXX  |  running   |
|  controller-1|  us-east-2a |  t2.micro       |  10.240.0.11   |  XX.XXX.XXX.XXX  |  running   |
|  controller-2|  us-east-2a |  t2.micro       |  10.240.0.12   |  XX.XXX.XXX.XXX  |  running   |
|  worker-0    |  us-east-2a |  t2.micro       |  10.240.0.20   |  XX.XXX.XXX.XXX  |  running   |
|  worker-1    |  us-east-2a |  t2.micro       |  10.240.0.21   |  XX.XXX.XXX.XXX  |  running   |
|  worker-2    |  us-east-2a |  t2.micro       |  10.240.0.22   |  XX.XXX.XXX.XXX  |  running   |
+--------------+-------------+-----------------+----------------+------------------+------------+
```

### Public IP Addresses

Store public IP addresses for EC2 instance and for elastic IP in a variable
called `PUBLIC_ADDRESS` so you don't have to query them each time:

```sh
declare -A "PUBLIC_ADDRESS=( $(aws ec2 describe-instances \
  --filter "Name=tag:Name,Values=controller-0,controller-1,controller-2,worker-0,worker-1,worker-2" "Name=instance-state-name,Values=running" \
  --output text --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0],PublicIpAddress]' \
  | xargs -n2 printf "[%s]=%s ") )"

PUBLIC_ADDRESS[kubernetes]=$(aws ec2 describe-addresses \
  --filters Name=tag:Name,Values=kubernetes-the-hard-way \
  --output text --query 'Addresses[0].PublicIp')
```

## Provisioning a CA and Generating TLS Certificates

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/04-certificate-authority.md)
with the following adjustments:

In the section [The Kubelet Client Certificates](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/04-certificate-authority.md#the-kubelet-client-certificates)
generate a certificate and private key for each Kubernetes worker node with
the following snippet instead:

> `PUBLIC_ADDRESS` variable should have been [initialized](#public-ip-addresses)

```sh
for i in 0 1 2; do
  instance="worker-${i}"
  INSTANCE_HOSTNAME="ip-10-240-0-2${i}"
  cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${INSTANCE_HOSTNAME}",
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

  EXTERNAL_IP=${PUBLIC_ADDRESS[${instance}]}

  INTERNAL_IP="10.240.0.2${i}"

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -hostname=${INSTANCE_HOSTNAME},${EXTERNAL_IP},${INTERNAL_IP} \
    -profile=kubernetes \
    ${instance}-csr.json | cfssljson -bare ${instance}
done
```

In the section [The Kubernetes API Server Certificate](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/04-certificate-authority.md#the-kubernetes-api-server-certificate)
generate the Kubernetes API Server certificate and private key with the following
snippet instead:

```sh
KUBERNETES_PUBLIC_ADDRESS=${PUBLIC_ADDRESS[kubernetes]}

CONTROLLER_INSTANCE_HOSTNAMES=ip-10-240-0-10,ip-10-240-0-11,ip-10-240-0-12

KUBERNETES_HOSTNAMES=kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local

cat > kubernetes-csr.json <<EOF
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
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.32.0.1,10.240.0.10,10.240.0.11,10.240.0.12,${CONTROLLER_INSTANCE_HOSTNAMES},${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,${KUBERNETES_HOSTNAMES} \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes
```

In the section [Distribute the Client and Server Certificates](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/04-certificate-authority.md#distribute-the-client-and-server-certificates)
copy the certificates and private keys with the following snippets instead:

```sh
for instance in worker-0 worker-1 worker-2; do
  scp -i kubernetes-the-hard-way.id_rsa \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ca.pem ${instance}-key.pem ${instance}.pem \
    ubuntu@${PUBLIC_ADDRESS[${instance}]}:~/
done
```

```sh
for instance in controller-0 controller-1 controller-2; do
  scp -i kubernetes-the-hard-way.id_rsa \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
    service-account-key.pem service-account.pem \
    ubuntu@${PUBLIC_ADDRESS[${instance}]}:~/
done
```

## Generating Kubernetes Configuration Files for Authentication

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/05-kubernetes-configuration-files.md)
with the following adjustments:

In the section [Kubernetes Public IP Address](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/05-kubernetes-configuration-files.md#kubernetes-public-ip-address)
retrieve the `kubernetes-the-hard-way` static IP address with the following
snippet instead:

> `PUBLIC_ADDRESS` variable should have been [initialized](#public-ip-addresses)

```sh
KUBERNETES_PUBLIC_ADDRESS=${PUBLIC_ADDRESS[kubernetes]}
```

In the section [The kubelet Kubernetes Configuration File](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/05-kubernetes-configuration-files.md#the-kubelet-kubernetes-configuration-file)
generate a kubeconfig file for each worker node with the following snippet instead:

```sh
for i in 0 1 2; do
  instance="worker-${i}"
  INSTANCE_HOSTNAME="ip-10-240-0-2${i}"

  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-credentials system:node:${INSTANCE_HOSTNAME} \
    --client-certificate=${instance}.pem \
    --client-key=${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${INSTANCE_HOSTNAME} \
    --kubeconfig=${instance}.kubeconfig

  kubectl config use-context default --kubeconfig=${instance}.kubeconfig
done
```

In the section [Distribute the Kubernetes Configuration Files](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/05-kubernetes-configuration-files.md#distribute-the-kubernetes-configuration-files)
copy kubeconfig files with the following snippets instead:

```sh
for instance in worker-0 worker-1 worker-2; do
  scp -i kubernetes-the-hard-way.id_rsa \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ${instance}.kubeconfig kube-proxy.kubeconfig \
    ubuntu@${PUBLIC_ADDRESS[${instance}]}:~/
done
```

```sh
for instance in controller-0 controller-1 controller-2; do
  scp -i kubernetes-the-hard-way.id_rsa \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig \
    ubuntu@${PUBLIC_ADDRESS[${instance}]}:~/
done
```

## Generating the Data Encryption Config and Key

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/06-data-encryption-keys.md)
with the following adjustments:

Copy the `encryption-config.yaml` with the following snippet instead:

> `PUBLIC_ADDRESS` variable should have been [initialized](#public-ip-addresses)

```sh
for instance in controller-0 controller-1 controller-2; do
  scp -i kubernetes-the-hard-way.id_rsa \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    encryption-config.yaml ubuntu@${PUBLIC_ADDRESS[${instance}]}:~/
done
```

## Bootstrapping the etcd Cluster

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/07-bootstrapping-etcd.md)
with the following adjustments:

In the section [Prerequisites](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/07-bootstrapping-etcd.md#prerequisites)
login to each controller instance using the following snippets instead:

controller-0:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-0" "Name=instance-state-name,Values=running" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i kubernetes-the-hard-way.id_rsa ubuntu@${external_ip}
```

controller-1:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-1" "Name=instance-state-name,Values=running" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i kubernetes-the-hard-way.id_rsa ubuntu@${external_ip}
```

controller-2:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=controller-2" "Name=instance-state-name,Values=running" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i kubernetes-the-hard-way.id_rsa ubuntu@${external_ip}
```

In the section [Configure the etcd Server](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/07-bootstrapping-etcd.md#configure-the-etcd-server)
retrieve the internal IP address for the current compute instance with the
following snippet instead:

```sh
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "${INTERNAL_IP}"
```

and the etcd member name:

```sh
ETCD_NAME=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^name" | cut -d"=" -f2)

echo "${ETCD_NAME}"
```

## Bootstrapping the Kubernetes Control Plane

Before following the guide instructions run the following command from the terminal
you used to create compute resources to store on each controller the value of
KUBERNETES_PUBLIC_ADDRESS that will need needed in later in this chapter:

> `PUBLIC_ADDRESS` variable should have been [initialized](#public-ip-addresses)

```sh
for instance in controller-0 controller-1 controller-2; do
  ssh -i kubernetes-the-hard-way.id_rsa \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ubuntu@${PUBLIC_ADDRESS[${instance}]} "echo "${KUBERNETES_PUBLIC_ADDRESS}" > KUBERNETES_PUBLIC_ADDRESS"
done
```

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/08-bootstrapping-kubernetes-controllers.md)
with the following adjustments:

SSH to each controller as described in [previous section](#bootstrapping-the-etcd-cluster).

In the section [Configure the Kubernetes API Server](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/08-bootstrapping-kubernetes-controllers.md#configure-the-kubernetes-api-server)
retrieve the internal IP address for the current compute instance with the
following snippet instead:

```sh
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "${INTERNAL_IP}"
```

and the Kubernetes public IP:

```sh
KUBERNETES_PUBLIC_ADDRESS=$(cat KUBERNETES_PUBLIC_ADDRESS)

echo "${KUBERNETES_PUBLIC_ADDRESS}"
```

In the section [Enable HTTP Health Checks](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/08-bootstrapping-kubernetes-controllers.md#enable-http-health-checks)
create and deploy Nginx configuration using the following snippets instead:

```sh
cat > default <<EOF
server {
  listen      80 default_server;
  server_name _;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF
```

```sh
{
  sudo mv default \
    /etc/nginx/sites-available/default

  sudo ln -f -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
}
```

In the section [The Kubernetes Frontend Load Balancer](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/08-bootstrapping-kubernetes-controllers.md#the-kubernetes-frontend-load-balancer)
create the external load balancer network resources with the following snippet
instead:

```sh
VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=tag:Name,Values=kubernetes-the-hard-way \
  --output text --query 'Vpcs[0].VpcId')

SUBNET_ID=$(aws ec2 describe-subnets \
  --filters Name=tag:Name,Values=kubernetes-the-hard-way \
  --output text --query 'Subnets[0].SubnetId')

KUBERNETES_PUBLIC_ADDRESS_ALLOCATION_ID=$(aws ec2 describe-addresses \
  --filters Name=tag:Name,Values=kubernetes-the-hard-way \
  --output text --query 'Addresses[0].AllocationId')

LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer \
  --name kubernetes-the-hard-way \
  --subnet-mappings SubnetId=${SUBNET_ID},AllocationId=${KUBERNETES_PUBLIC_ADDRESS_ALLOCATION_ID} \
  --scheme internet-facing \
  --type network \
  --tags 'Key=Name,Value=kubernetes-the-hard-way' \
  --output text --query 'LoadBalancers[].LoadBalancerArn')

TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
  --name kubernetes-the-hard-way \
  --protocol TCP \
  --port 6443 \
  --vpc-id ${VPC_ID} \
  --target-type ip \
  --health-check-protocol HTTP \
  --health-check-port 80 \
  --health-check-path /healthz \
  --tags 'Key=Name,Value=kubernetes-the-hard-way' \
  --output text --query 'TargetGroups[].TargetGroupArn')

aws elbv2 register-targets \
  --target-group-arn ${TARGET_GROUP_ARN} \
  --targets Id=10.240.0.1{0,1,2}

aws elbv2 create-listener \
  --load-balancer-arn ${LOAD_BALANCER_ARN} \
  --protocol TCP \
  --port 6443 \
  --default-actions Type=forward,TargetGroupArn=${TARGET_GROUP_ARN} \
  --tags 'Key=Name,Value=kubernetes-the-hard-way' \
  --output text --query 'Listeners[].ListenerArn'
```

In the section [Verification](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/08-bootstrapping-kubernetes-controllers.md#verification-1)
retrieve the `kubernetes-the-hard-way` static IP address with the following
snippet instead:

```sh
KUBERNETES_PUBLIC_ADDRESS=${PUBLIC_ADDRESS[kubernetes]}
```

## Bootstrapping the Kubernetes Worker Nodes

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/09-bootstrapping-kubernetes-workers.md)
with the following adjustments:

In the section [Prerequisites](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/09-bootstrapping-kubernetes-workers.md#prerequisites)
login to each worker instance using the following snippets instead:

worker-0:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=worker-0" "Name=instance-state-name,Values=running" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i kubernetes-the-hard-way.id_rsa ubuntu@${external_ip}
```

worker-1:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=worker-1" "Name=instance-state-name,Values=running" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i kubernetes-the-hard-way.id_rsa ubuntu@${external_ip}
```

worker-2:

```sh
external_ip=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=worker-2" "Name=instance-state-name,Values=running" \
  --output text --query 'Reservations[].Instances[].PublicIpAddress')

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i kubernetes-the-hard-way.id_rsa ubuntu@${external_ip}
```

In the section [Configure CNI Networking](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/09-bootstrapping-kubernetes-workers.md#configure-cni-networking)
retrieve the Pod CIDR range for the current compute instance with the following
snippet instead:

```sh
POD_CIDR=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^pod-cidr" | cut -d"=" -f2)

echo "${POD_CIDR}"
```

In the section [Configure the Kubelet](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/09-bootstrapping-kubernetes-workers.md#configure-the-kubelet)
before executing any command set HOSTNAME in the local shell with the following
snippet:

```sh
HOSTNAME=$(curl -s http://169.254.169.254/latest/user-data/ \
  | tr "|" "\n" | grep "^name" | cut -d"=" -f2)

echo "${HOSTNAME}"
```

In the section [Verification](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/09-bootstrapping-kubernetes-workers.md#verification)
list the registered Kubernetes nodes with the following snippet instead:

> `PUBLIC_ADDRESS` variable should have been [initialized](#public-ip-addresses)

```sh
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i kubernetes-the-hard-way.id_rsa ubuntu@${PUBLIC_ADDRESS[controller-0]} \
  kubectl get nodes --kubeconfig admin.kubeconfig
```

Output:

```txt
NAME             STATUS   ROLES    AGE   VERSION
ip-10-240-0-20   Ready    <none>   16s   v1.21.0
ip-10-240-0-21   Ready    <none>   16s   v1.21.0
ip-10-240-0-22   Ready    <none>   17s   v1.21.0
```

## Configuring kubectl for Remote Access

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/10-configuring-kubectl.md)
with the following adjustments:

In the section [The Admin Kubernetes Configuration File](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/10-configuring-kubectl.md#the-admin-kubernetes-configuration-file)
generate a kubeconfig file suitable for authenticating as the `admin` user with
the following snippet instead:

> `PUBLIC_ADDRESS` variable should have been [initialized](#public-ip-addresses)

```sh
{
  KUBERNETES_PUBLIC_ADDRESS=${PUBLIC_ADDRESS[kubernetes]}

  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem

  kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin

  kubectl config use-context kubernetes-the-hard-way
}
```

In the section [Verification](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/10-configuring-kubectl.md#verification)
the output of the command `kubectl get nodes` should look like this instead:

```txt
NAME             STATUS   ROLES    AGE   VERSION
ip-10-240-0-20   Ready    <none>   91s   v1.21.0
ip-10-240-0-21   Ready    <none>   91s   v1.21.0
ip-10-240-0-22   Ready    <none>   91s   v1.21.0
```

## Provisioning Pod Network Routes

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/11-pod-network-routes.md)

### The Routing Table

Print the internal IP address and Pod CIDR range for each worker instance:

```sh
for instance in worker-0 worker-1 worker-2; do
  instance_id_ip=($(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" "Name=instance-state-name,Values=running" \
    --output text --query 'Reservations[].Instances[0].[InstanceId,PrivateIpAddress]'))

  pod_cidr="$(aws ec2 describe-instance-attribute \
    --instance-id "${instance_id_ip[0]}" \
    --attribute userData \
    --output text --query 'UserData.Value' \
    | base64 --decode | tr "|" "\n" | grep "^pod-cidr" | cut -d'=' -f2)"

  echo "${instance_id_ip[1]} ${pod_cidr}"
done
```

### Routes

Create network routes for each worker instance:

```sh
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
    --filters Name=tag:Name,Values=kubernetes-the-hard-way \
    --output text --query 'RouteTables[0].RouteTableId')

for instance in worker-0 worker-1 worker-2; do
  instance_id=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].InstanceId')

  pod_cidr="$(aws ec2 describe-instance-attribute \
    --instance-id "${instance_id}" \
    --attribute userData \
    --output text --query 'UserData.Value' \
    | base64 --decode | tr "|" "\n" | grep "^pod-cidr" | cut -d'=' -f2)"

  aws ec2 create-route \
    --route-table-id "${ROUTE_TABLE_ID}" \
    --destination-cidr-block "${pod_cidr}" \
    --instance-id "${instance_id}"
done
```

List the routes:

```sh
aws ec2 describe-route-tables \
  --filters Name=tag:Name,Values=kubernetes-the-hard-way \
  --query 'sort_by(RouteTables[0].Routes[],&DestinationCidrBlock)[].{Destination:DestinationCidrBlock,InstanceId:InstanceId,GatewayId:GatewayId}' \
  --output table
```

Output:

```txt
-------------------------------------------------------------------
|                       DescribeRouteTables                       |
+---------------+-------------------------+-----------------------+
|  Destination  |        GatewayId        |      InstanceId       |
+---------------+-------------------------+-----------------------+
|  0.0.0.0/0    |  igw-0acc027e68bb7af40  |  None                 |
|  10.200.0.0/24|  None                   |  i-088499c5e8f5a054e  |
|  10.200.1.0/24|  None                   |  i-03531f12b3dc8af3c  |
|  10.200.2.0/24|  None                   |  i-02df4bbc8fbc75733  |
|  10.240.0.0/24|  local                  |  None                 |
+---------------+-------------------------+-----------------------+
```

## Deploying the DNS Cluster Add-on

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/12-dns-addon.md).

## Smoke Test

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/13-smoke-test.md)
with the following adjustments:

In the section [Data Encryption](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/13-smoke-test.md#data-encryption)
print a hexdump of the `kubernetes-the-hard-way` secret stored in etcd with the
following snippet instead:

> `PUBLIC_ADDRESS` variable should have been [initialized](#public-ip-addresses)

```sh
 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
   -i kubernetes-the-hard-way.id_rsa \
   ubuntu@${PUBLIC_ADDRESS[controller-0]} \
   "sudo ETCDCTL_API=3 etcdctl get \
   --endpoints=https://127.0.0.1:2379 \
   --cacert=/etc/etcd/ca.pem \
   --cert=/etc/etcd/kubernetes.pem \
   --key=/etc/etcd/kubernetes-key.pem\
   /registry/secrets/default/kubernetes-the-hard-way | hexdump -C"
```

In the section [Services](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/13-smoke-test.md#services)
create firewall rule that allows remote access to nginx node port using the following
snippet instead:

```sh
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
--filters "Name=tag:Name,Values=kubernetes-the-hard-way" \
--output text --query 'SecurityGroups[0].GroupId')

aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port ${NODE_PORT} \
  --cidr 0.0.0.0/0
```

and retrieve the external IP address of a worker instance using the following
snippet instead:

```sh
EXTERNAL_IP=${PUBLIC_ADDRESS[worker-0]}

echo ${EXTERNAL_IP}
```

## Cleaning Up

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/14-cleanup.md)

### Compute Instances

```sh
INSTANCE_IDS=($(aws ec2 describe-instances \
      --filter "Name=tag:Name,Values=controller-0,controller-1,controller-2,worker-0,worker-1,worker-2" "Name=instance-state-name,Values=running" \
      --output text --query 'Reservations[].Instances[].InstanceId'))

aws ec2 terminate-instances \
  --instance-ids ${INSTANCE_IDS[@]} \
  --query 'TerminatingInstances[].InstanceId' \
  --output table

aws ec2 delete-key-pair \
  --key-name kubernetes-the-hard-way

aws ec2 wait instance-terminated \
  --instance-ids ${INSTANCE_IDS[@]}
```

### Networking

Delete load balancer:

```sh
LOAD_BALANCER_ARN=$(aws elbv2 describe-load-balancers \
  --name kubernetes-the-hard-way \
  --output text --query 'LoadBalancers[0].LoadBalancerArn')

LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn "${LOAD_BALANCER_ARN}" \
  --output text --query 'Listeners[0].ListenerArn')

aws elbv2 delete-listener \
  --listener-arn "${LISTENER_ARN}"

aws elbv2 delete-load-balancer \
  --load-balancer-arn "${LOAD_BALANCER_ARN}"

TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --name kubernetes-the-hard-way \
  --output text --query 'TargetGroups[0].TargetGroupArn')

aws elbv2 delete-target-group \
  --target-group-arn "${TARGET_GROUP_ARN}"
```

Delete security group:

```sh
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=kubernetes-the-hard-way" \
  --output text --query 'SecurityGroups[0].GroupId')

aws ec2 delete-security-group \
  --group-id "${SECURITY_GROUP_ID}"
```

Delete route table:

```sh
ROUTE_TABLE_ASSOCIATION_ID="$(aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --output text --query 'RouteTables[].Associations[].RouteTableAssociationId')"

aws ec2 disassociate-route-table \
  --association-id "${ROUTE_TABLE_ASSOCIATION_ID}"

ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=kubernetes-the-hard-way" \
  --output text --query 'RouteTables[0].RouteTableId')

aws ec2 delete-route-table \
  --route-table-id "${ROUTE_TABLE_ID}"
```

Delete Internet gateway:

```sh
INTERNET_GATEWAY_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=kubernetes-the-hard-way" \
  --output text --query 'InternetGateways[0].InternetGatewayId')

aws ec2 detach-internet-gateway \
  --internet-gateway-id "${INTERNET_GATEWAY_ID}" \
  --vpc-id "${VPC_ID}"

aws ec2 delete-internet-gateway \
  --internet-gateway-id "${INTERNET_GATEWAY_ID}"
```

Delete subnet and VPC:

```sh
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters Name=tag:Name,Values=kubernetes-the-hard-way \
  --output text --query 'Subnets[0].SubnetId')

aws ec2 delete-subnet \
  --subnet-id "${SUBNET_ID}"

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=tag:Name,Values=kubernetes-the-hard-way \
  --output text --query 'Vpcs[0].VpcId')

aws ec2 delete-vpc \
  --vpc-id "${VPC_ID}"
```

Release KUBERNETES_PUBLIC_ADDRESS:

```sh
ALLOCATION_ID=$(aws ec2 describe-addresses \
  --filters Name=tag:Name,Values=kubernetes-the-hard-way \
  --output text --query 'Addresses[0].AllocationId')

aws ec2 release-address \
  --allocation-id ${ALLOCATION_ID}
```

Ensure there are no more resources left:

```sh
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Name,Values=kubernetes-the-hard-way \
  --query 'sort_by(ResourceTagMappingList, &ResourceARN)[].ResourceARN' \
  --output table
```
