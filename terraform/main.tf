locals {
  vpc_cidr = "10.240.0.0/24"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Name = "kubernetes-the-hard-way"
    }
  }
}

resource "aws_vpc" "k8s" {
  cidr_block = local.vpc_cidr
}

resource "aws_subnet" "k8s" {
  vpc_id     = aws_vpc.k8s.id
  cidr_block = local.vpc_cidr
}

resource "aws_internet_gateway" "k8s" {
  vpc_id = aws_vpc.k8s.id
}

resource "aws_route_table" "k8s" {
  vpc_id = aws_vpc.k8s.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s.id
  }
}

resource "aws_route_table_association" "k8s" {
  subnet_id      = aws_subnet.k8s.id
  route_table_id = aws_route_table.k8s.id
}

resource "aws_security_group" "k8s" {
  name   = "kubernetes-the-hard-way"
  vpc_id = aws_vpc.k8s.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "tls_private_key" "k8s" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "aws_key_pair" "k8s" {
  key_name   = "kubernetes-the-hard-way"
  public_key = tls_private_key.k8s.public_key_openssh
}

data "aws_ami" "k8s" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }
}

resource "aws_instance" "k8s" {
  for_each = toset(["jumpbox", "server", "node-0", "node-1"])

  ami                         = data.aws_ami.k8s.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.k8s.key_name
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.k8s.id

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Enable root login via SSH
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart sshd

    # Fix authorized_keys to allow ssh-rsa lines
    sed -i 's/.*ssh-rsa/ssh-rsa/' /root/.ssh/authorized_keys

    # Add 127.0.1.1 if not in /etc/hosts
    grep -q '127.0.1.1' /etc/hosts || echo '127.0.1.1 localhost' >> /etc/hosts
  EOF

  tags = {
    Name = each.key
  }
}

resource "local_sensitive_file" "private_key" {
  filename        = "${path.module}/kubernetes-the-hard-way.id_rsa"
  content         = tls_private_key.k8s.private_key_pem
  file_permission = "0600"
}

resource "local_file" "machines" {
  filename = "${path.module}/machines.txt"

  content = <<-EOF
    ${aws_instance.k8s["server"].private_ip} server.kubernetes.local server
    ${aws_instance.k8s["node-0"].private_ip} node-0.kubernetes.local node-0 10.200.0.0/24
    ${aws_instance.k8s["node-1"].private_ip} node-1.kubernetes.local node-1 10.200.1.0/24
  EOF
}

resource "terraform_data" "jumpbox_files" {
  triggers_replace = [
    aws_instance.k8s["jumpbox"].public_ip
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.k8s["jumpbox"].public_ip
    user        = "root"
    private_key = tls_private_key.k8s.private_key_pem
  }

  provisioner "file" {
    source      = local_file.machines.filename
    destination = "/root/machines.txt"
  }

  provisioner "file" {
    source      = local_sensitive_file.private_key.filename
    destination = "/root/.ssh/id_rsa"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 0600 /root/.ssh/id_rsa",
      "sed -i 's/^127.0.1.1.*/127.0.1.1\tjumpbox/' /etc/hosts",
      "hostnamectl set-hostname jumpbox",
      "systemctl restart systemd-hostnamed"
    ]
  }
}
