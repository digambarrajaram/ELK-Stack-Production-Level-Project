# Fetch an Ubuntu 22.04 LTS Machine Image automatically
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "elk_instance" {
    ami = data.aws_ami.ubuntu.id
    instance_type = var.instance_type
    key_name = var.key_name

    # IMDSv2 enforced (security best practice — required by AWS Security Hub)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # enforces IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true   # EBS encryption at rest
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io docker-compose-plugin git

    # Allow docker without sudo
    usermod -aG docker ubuntu

    # Set vm.max_map_count required by Elasticsearch
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    sysctl -w vm.max_map_count=262144

    # Clone your repo (update URL after pushing to GitHub)
    # git clone https://github.com/YOUR_USERNAME/elk-stack-project.git /home/ubuntu/elk-stack
  EOF

    tags = {
      Name = var.instance_name
      Project = var.project
    }
}

resource "aws_security_group" "elk_sg" {
    name = "elk-stack-sg"
    description = "Security group for elk stack"

    tags = {
      Name = "elk-stack-sg"
      Project = var.project
    }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 22
  to_port = 22
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 443
  to_port = 443
}
resource "aws_vpc_security_group_ingress_rule" "logstash" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 5044
  to_port = 5044
}
resource "aws_vpc_security_group_ingress_rule" "kibana" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 5601
  to_port = 5601
}

resource "aws_vpc_security_group_ingress_rule" "web_API_port_Elastic_Logstash" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 9600
  to_port = 9600
}

resource "aws_vpc_security_group_ingress_rule" "ElasticSearch" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 9200
  to_port = 9200
}
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 80
  to_port = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4         = var.internet_route
  ip_protocol       = "-1" # Semantically represents all protocols
}