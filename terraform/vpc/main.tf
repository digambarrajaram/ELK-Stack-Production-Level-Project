#aws vpc
resource "aws_vpc" "elk_vpc" {
    cidr_block = var.cidr_block
    enable_dns_hostnames = true
    enable_dns_support = true
    tags = {
      Name = var.vpc_name
      Project = var.project
    }
}

resource "aws_internet_gateway" "elk_igw" {
    vpc_id = aws_vpc.elk_vpc.id
    tags = {
      Name = "${var.vpc_name}-igw"
      Project = var.project
    }
}

resource "aws_subnet" "elk_subnet_public" {
    vpc_id = aws_vpc.elk_vpc.id
    cidr_block = var.public_subnet_cidr_block
    availability_zone = var.az
    map_public_ip_on_launch = true
    tags = {
      Name = "${var.vpc_name}-subnet"
      Project = var.project
    }
}


resource "aws_route_table" "elk_public_rt" {
    vpc_id = aws_vpc.elk_vpc.id
    route {
        cidr_block = var.internet_route
        gateway_id = aws_internet_gateway.elk_igw.id
    }
    tags = {
      Name = "${var.vpc_name}-rt"
      Project = var.project
    }
}

resource "aws_route_table_association" "elk_public_assoc" {
    subnet_id = aws_subnet.elk_subnet_public.id
    route_table_id = aws_route_table.elk_public_rt.id
}



resource "aws_security_group" "elk_sg" {
    name = "elk-stack-sg"
    vpc_id = aws_vpc.elk_vpc.id
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