# Kubernetes The Hard Way - AWS

Welcome to the AWS companion to [Kubernetes The Hard
Way](https://github.com/kelseyhightower/kubernetes-the-hard-way/) guide.

As of [a9cb5f7](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/a9cb5f7ba50b3ed496a18a09c273941f80c6375a)
the original guide has been rewritten to be cloud agnostic. The cluster being
created is private (i.e. connectable only from the VPC) and has a one-node
control plane which removes the need for a load balancer and public Internet
access. This also simplifies significantly this guide which is now only limited
to provisioning VPC and EC2 instances, and performing the cleanup at the end.

This guide has been tested with revision [52eb26d](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/52eb26dad1a3e9e8083a899bc854421eb4842a73)
of the original guide which provides the details about setting up
**Kubernetes v1.32**.

You can also find [previous version of this guide](https://github.com/slawekzachcial/kubernetes-the-hard-way-aws/tree/f1313c78a9dafe17c39dc0094db5605b04d723f1).

* [Prerequisites](#prerequisites)
  * [Amazon Web Services](#amazon-web-services)
  * [AWS CLI](#aws-cli)
    * [Networking](#networking)
    * [Compute Instances](#compute-instances)
    * [Machine Database](#machine-database)
    * [SSH Access](#ssh-access)
    * [Hosts File](#hosts-file)
  * [Terraform](#terraform)
  * [Connecting to Jumpbox](#connecting-to-jumpbox)
* **Original Guide** [Labs](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/52eb26dad1a3e9e8083a899bc854421eb4842a73#labs)
* [Cleaning Up](#cleaning-up)
  * [AWS CLI Clean Up](#aws-cli-clean-up)
    * [Networking Clean Up](#networking-clean-up)
    * [Compute Instances Clean Up](#compute-instances-clean-up)
  * [Terraform Clean Up](#terraform-clean-up)

## Prerequisites

### Amazon Web Services

The commands below create VPC and EC2 instances to deploy Kubernetes cluster
into [Amazon Web Services](https://aws.amazon.com).

Install AWS CLI following instructions at <https://aws.amazon.com/cli/>.

Details how to configure AWS CLI are available in
[this guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html).

Check out [the guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/52eb26dad1a3e9e8083a899bc854421eb4842a73/docs/01-prerequisites.md)
to see the EC2 instance requirements.

### AWS CLI

The following subsections provide the commands to provision VPC, EC2 and prepare
them to execute commands from the orginal tutorial.

#### Networking

```sh
# Create VPC:

VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.240.0.0/24 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=kubernetes-the-hard-way}]' \
  --output text --query 'Vpc.VpcId')

# Create Subnet:

SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block 10.240.0.0/24 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=kubernetes-the-hard-way}]' \
  --output text --query 'Subnet.SubnetId')

# Create Internet Gateway:

INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=kubernetes-the-hard-way}]' \
  --output text --query 'InternetGateway.InternetGatewayId')

aws ec2 attach-internet-gateway \
  --internet-gateway-id ${INTERNET_GATEWAY_ID} \
  --vpc-id ${VPC_ID}

# Create Route Table:

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

# Create Security Group:

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
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# List the created security group rules:

aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=${SECURITY_GROUP_ID}" \
  --query 'sort_by(SecurityGroupRules, &CidrIpv4)[].{a_Protocol:IpProtocol,b_FromPort:FromPort,c_ToPort:ToPort,d_Cidr:CidrIpv4,e_Egress:IsEgress}' \
  --output table
```

Output:

```txt
-----------------------------------------------------------------------
|                     DescribeSecurityGroupRules                      |
+------------+-------------+-----------+-----------------+------------+
| a_Protocol | b_FromPort  | c_ToPort  |     d_Cidr      | e_Egress   |
+------------+-------------+-----------+-----------------+------------+
|  tcp       |  22         |  22       |  0.0.0.0/0      |  False     |
|  -1        |  -1         |  -1       |  0.0.0.0/0      |  True      |
|  -1        |  -1         |  -1       |  10.240.0.0/24  |  False     |
+------------+-------------+-----------+-----------------+------------+
```

#### Compute Instances

```sh
# Create SSH key pair:

aws ec2 create-key-pair \
  --key-name kubernetes-the-hard-way \
  --output text --query 'KeyMaterial' \
  > kubernetes-the-hard-way.id_rsa

chmod 600 kubernetes-the-hard-way.id_rsa

# Find instance image ID:

IMAGE_ID=$(aws ec2 describe-images --owners 136693071363 \
  --filters \
  'Name=root-device-type,Values=ebs' \
  'Name=architecture,Values=x86_64' \
  'Name=name,Values=debian-12-amd64-*' \
  --output text --query 'sort_by(Images[],&Name)[-1].ImageId')

echo ${IMAGE_ID}

# Create EC2 Instances:

INSTANCE_IDS=()
for i in jumpbox server node-0 node-1; do
  instance_id=$(aws ec2 run-instances \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes-the-hard-way \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t2.micro \
    --subnet-id ${SUBNET_ID} \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${i}},{Key=Project,Value=kubernetes-the-hard-way}]" \
    --output text --query 'Instances[].InstanceId')

  INSTANCE_IDS+=($instance_id)
done

aws ec2 wait instance-running --instance-ids "${INSTANCE_IDS[@]}"

JUMPBOX_IP=$(aws ec2 describe-instances \
  --instance-ids ${INSTANCE_IDS[@]} \
  --filters "Name=tag:Name,Values=jumpbox" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output text)

MACHINES_IPS=($(aws ec2 describe-instances \
  --instance-ids ${INSTANCE_IDS[@]} \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[?Tags[?Key=='Name' && Value!='jumpbox']].PublicIpAddress" \
  --output text))

# List the compute instances in your default region:

aws ec2 describe-instances \
  --filters Name=vpc-id,Values=${VPC_ID} \
  --query 'sort_by(Reservations[].Instances[],&PrivateIpAddress)[].{d_INTERNAL_IP:PrivateIpAddress,e_EXTERNAL_IP:PublicIpAddress,a_NAME:Tags[?Key==`Name`].Value | [0],b_ZONE:Placement.AvailabilityZone,c_MACHINE_TYPE:InstanceType,f_STATUS:State.Name}' \
  --output table
```

Output:

```txt
--------------------------------------------------------------------------------------------
|                                     DescribeInstances                                    |
+---------+-------------+-----------------+----------------+------------------+------------+
| a_NAME  |   b_ZONE    | c_MACHINE_TYPE  | d_INTERNAL_IP  |  e_EXTERNAL_IP   | f_STATUS   |
+---------+-------------+-----------------+----------------+------------------+------------+
|  node-0 |  us-east-2b |  t2.micro       |  10.240.0.108  |  3.129.58.106    |  running   |
|  node-1 |  us-east-2b |  t2.micro       |  10.240.0.126  |  18.222.127.243  |  running   |
|  server |  us-east-2b |  t2.micro       |  10.240.0.196  |  18.117.164.54   |  running   |
|  jumpbox|  us-east-2b |  t2.micro       |  10.240.0.70   |  18.219.238.229  |  running   |
+---------+-------------+-----------------+----------------+------------------+------------+
```

#### Machine Database

On your workstation (not jumpbox) run the following commands to create and copy
`machines.txt`. The commands below generate the file that is described in
[Machine Database](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/52eb26dad1a3e9e8083a899bc854421eb4842a73/docs/03-compute-resources.md#machine-database)
section of the original guide.

Note that the `scp` command copies the file to `/root/machines.txt`. Once you
clone, on the Jumpbox, the guide Git repository, you need to move this file to
`/root/kubernetes-the-hard-way` folder.

```sh
SERVER_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=server" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].[PrivateIpAddress]" \
  --output text)
NODE0_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=node-0" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].[PrivateIpAddress]" \
  --output text)
NODE1_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=node-1" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].[PrivateIpAddress]" \
  --output text)

cat > machines.txt <<EOF
$SERVER_IP server.kubernetes.local server
$NODE0_IP node-0.kubernetes.local node-0 10.200.0.0/24
$NODE1_IP node-1.kubernetes.local node-1 10.200.1.0/24
EOF

scp -i ./kubernetes-the-hard-way.id_rsa machines.txt admin@$JUMPBOX_IP:/home/admin
ssh -i ./kubernetes-the-hard-way.id_rsa admin@$JUMPBOX_IP "sudo mv /home/admin/machines.txt /root/"
```

#### SSH Access

To enable root SSH access on `server`, `node-0` and `node-1`, and the SSH
connectivity from `jumpbox` to these servers, run the following commands on
your workstation (not jumpbox).

Note that these commands replace commands from the original guide in sections:

* [Enable root SSH Access](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/03-compute-resources.md#enable-root-ssh-access)
* [Generate and Distribute SSH Keys](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/03-compute-resources.md#generate-and-distribute-ssh-keys)

```sh
for ip in $JUMPBOX_IP ${MACHINES_IPS[@]}; do
  ssh -i ./kubernetes-the-hard-way.id_rsa \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    admin@$ip \
    "sudo sed -i \
    's/^#*PermitRootLogin.*/PermitRootLogin yes/' \
    /etc/ssh/sshd_config \
    && sudo systemctl restart sshd \
    && sudo sed -i 's/.*ssh-rsa/ssh-rsa/' /root/.ssh/authorized_keys"
done
scp -i ./kubernetes-the-hard-way.id_rsa ./kubernetes-the-hard-way.id_rsa root@$JUMPBOX_IP:/root/.ssh/id_rsa
```

#### Hosts File

AWS EC2 instances `/etc/hosts` do not have an entry for `127.0.1.1` loopback
address referenced in the guide. Let's fix it.

```sh
for ip in ${MACHINES_IPS[@]}; do
  ssh -i ./kubernetes-the-hard-way.id_rsa \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    admin@$ip \
    "grep -q '127.0.1.1' /etc/hosts || echo '127.0.1.1 localhost' | sudo tee -a /etc/hosts"
done
```

### Terraform

If you prefer a "no hard way" and you have Terraform installed, as an
alternative to running the AWS CLI commands above you can run the Terraform
configuration files:

```sh
cd terraform
terraform init
terraform apply
JUMPBOX_IP=$(terraform output -raw jumpbox_ip)
```

### Connecting to Jumpbox

To connect to `jumpbox` as `root` run the following command:

```sh
ssh -i ./kubernetes-the-hard-way.id_rsa -o SetEnv='LC_ALL=C.UTF-8 LANG=C.UTF-8' root@$JUMPBOX_IP
```

## Cleaning Up

### AWS CLI Clean Up

The following subsections provide the commands to clean-up EC2, and VPC.

#### Compute Instances Clean Up

```sh
INSTANCE_IDS=($(aws ec2 describe-instances \
      --filter "Name=tag:Name,Values=jumpbox,server,node-0,node-1" "Name=instance-state-name,Values=running" \
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

#### Networking Clean Up

```sh
# Delete security group:

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=kubernetes-the-hard-way" \
  --output text --query 'SecurityGroups[0].GroupId')

aws ec2 delete-security-group \
  --group-id "${SECURITY_GROUP_ID}"

# Delete route table:

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

# Delete Internet gateway:

INTERNET_GATEWAY_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=kubernetes-the-hard-way" \
  --output text --query 'InternetGateways[0].InternetGatewayId')

aws ec2 detach-internet-gateway \
  --internet-gateway-id "${INTERNET_GATEWAY_ID}" \
  --vpc-id "${VPC_ID}"

aws ec2 delete-internet-gateway \
  --internet-gateway-id "${INTERNET_GATEWAY_ID}"

# Delete subnet and VPC:

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

# Ensure there are no more resources left:

aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Name,Values=kubernetes-the-hard-way \
  --query 'sort_by(ResourceTagMappingList, &ResourceARN)[].ResourceARN' \
  --output table
aws ec2 describe-instances \
  --query "Reservations[].Instances[].{InstanceId:InstanceId, Name:Tags[?Key=='Name']|[0].Value, State:State.Name}" \
  --output table
```

### Terraform Clean Up

If you provisioned the guide resources with Terraform, run the following
command to clean them up:

```sh
cd terraform
terraform destroy
```
