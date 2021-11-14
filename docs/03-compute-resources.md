# Provisioning Compute Resources

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/03-compute-resources.md)

## Networking

### Virtual Private Cloud Network

Create VPC:

```sh
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

Create DHCP Options:

> Note:
> If you are deploying into `us-east-1` (your `AWS_DEFAULT_REGION=us-east-1`),
> change domain name value below from `${AWS_DEFAULT_REGION}.compute.internal`
> to `${AWS_DEFAULT_REGION}.ec2.internal`.

```sh
DHCP_OPTION_SET_ID=$(aws ec2 create-dhcp-options \
  --dhcp-configuration \
    Key=domain-name,Values=${AWS_DEFAULT_REGION}.compute.internal \
    Key=domain-name-servers,Values=AmazonProvidedDNS \
  --output text --query 'DhcpOptions.DhcpOptionsId')

aws ec2 create-tags \
  --resources ${DHCP_OPTION_SET_ID} \
  --tags Key=Name,Value=kubernetes-the-hard-way

aws ec2 associate-dhcp-options \
  --dhcp-options-id ${DHCP_OPTION_SET_ID} \
  --vpc-id ${VPC_ID}
```

Create Subnet:

```sh
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block 10.240.0.0/24 \
  --output text --query 'Subnet.SubnetId')

aws ec2 create-tags \
  --resources ${SUBNET_ID} \
  --tags Key=Name,Value=kubernetes-the-hard-way
```

Create Internet Gateway:

```sh
INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway \
  --output text --query 'InternetGateway.InternetGatewayId')

aws ec2 create-tags \
  --resources ${INTERNET_GATEWAY_ID} \
  --tags Key=Name,Value=kubernetes-the-hard-way

aws ec2 attach-internet-gateway \
  --internet-gateway-id ${INTERNET_GATEWAY_ID} \
  --vpc-id ${VPC_ID}
```

Create Route Table:

```sh
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} \
  --output text --query 'RouteTable.RouteTableId')

aws ec2 create-tags \
  --resources ${ROUTE_TABLE_ID} \
  --tags Key=Name,Value=kubernetes-the-hard-way

aws ec2 associate-route-table \
  --route-table-id ${ROUTE_TABLE_ID} \
  --subnet-id ${SUBNET_ID}

aws ec2 create-route \
  --route-table-id ${ROUTE_TABLE_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${INTERNET_GATEWAY_ID}
```

### Firewall Rules (aka Security Group)

```sh
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name kubernetes-the-hard-way \
  --description "Kubernetes The Hard Way security group" \
  --vpc-id ${VPC_ID} \
  --output text --query 'GroupId')

aws ec2 create-tags \
  --resources ${SECURITY_GROUP_ID} \
  --tags Key=Name,Value=kubernetes-the-hard-way

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
  --query 'SecurityGroupRules[*].{a_Protocol:IpProtocol,b_FromPort:FromPort,c_ToPort:ToPort,d_Cidr:CidrIpv4}' \
  --output table
```

Output:

```
-----------------------------------------------------------
|               DescribeSecurityGroupRules                |
+------------+-------------+-----------+------------------+
| a_Protocol | b_FromPort  | c_ToPort  |     d_Cidr       |
+------------+-------------+-----------+------------------+
|  -1        |  -1         |  -1       |  10.240.0.0/24   |
|  tcp       |  22         |  22       |  0.0.0.0/0       |
|  -1        |  -1         |  -1       |  10.200.0.0/16   |
|  icmp      |  -1         |  -1       |  0.0.0.0/0       |
|  tcp       |  6443       |  6443     |  0.0.0.0/0       |
|  -1        |  -1         |  -1       |  0.0.0.0/0       |
+------------+-------------+-----------+------------------+
```

### Kubernetes Public IP Address

```sh
ALLOCATION_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --output text --query 'AllocationId')

aws ec2 create-tags \
  --resources ${ALLOCATION_ID} \
  --tags Key=Name,Value=kubernetes-the-hard-way
```

Verify the address was created in your default region:

```sh
aws ec2 describe-addresses --allocation-ids ${ALLOCATION_ID}
```

### Kubernetes Public Address <-- TO BE MOVED

> TODO: move the LB creation section to where it belongs as per original guide

```sh
LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer \
  --name kubernetes \
  --subnets ${SUBNET_ID} \
  --scheme internet-facing \
  --type network \
  --output text --query 'LoadBalancers[].LoadBalancerArn')
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
aws elbv2 create-listener \
  --load-balancer-arn ${LOAD_BALANCER_ARN} \
  --protocol TCP \
  --port 6443 \
  --default-actions Type=forward,TargetGroupArn=${TARGET_GROUP_ARN} \
  --output text --query 'Listeners[].ListenerArn'
```

```sh
KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LOAD_BALANCER_ARN} \
  --output text --query 'LoadBalancers[].DNSName')
```

## Compute Instances

### SSH Key Pair

```sh
mkdir -p ssh

aws ec2 create-key-pair \
  --key-name kubernetes-the-hard-way \
  --output text --query 'KeyMaterial' \
  > ssh/kubernetes.id_rsa
chmod 600 ssh/kubernetes.id_rsa
```

### Instance Image

```sh
IMAGE_ID=$(aws ec2 describe-images --owners 099720109477 \
  --filters \
  'Name=root-device-type,Values=ebs' \
  'Name=architecture,Values=x86_64' \
  'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*' \
  --query 'sort_by(Images[],&Name)[-1].ImageId' \
  --output text)

echo ${IMAGE_ID}
```

### Kubernetes Controllers

Using `t2.micro` instead of `t2.small` as `t2.micro` is covered by AWS free tier

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
    --output text --query 'Instances[].InstanceId')
  aws ec2 modify-instance-attribute \
    --instance-id ${instance_id} \
    --no-source-dest-check
  aws ec2 create-tags \
    --resources ${instance_id} \
    --tags "Key=Name,Value=worker-${i}"
done
```

### Verification

List the compute instances in your default region:

```sh
aws ec2 describe-instances \
  --filters Name=vpc-id,Values=${VPC_ID} \
  --query 'sort_by(Reservations[].Instances[],&PrivateIpAddress)[].{d_INTERNAL_IP:PrivateIpAddress,e_EXTERNAL_IP:PublicIpAddress,a_NAME:Tags[?Key==`Name`].Value | [0],b_ZONE:Placement.AvailabilityZone,c_MACHINE_TYPE:InstanceType,f_STATUS:State.Name}' \
  --output table
```

Output:

```
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

Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)
