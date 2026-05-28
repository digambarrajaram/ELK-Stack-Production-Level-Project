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
    availability_zone = var.aws_region
    map_public_ip_on_launch = true
    tags = {
      Name = "${var.vpc_name}-subnet"
      Project = var.project
    }
}

resource "aws_subnet" "elk_subnet_private" {
    vpc_id = aws_vpc.elk_vpc.id
    cidr_block = var.private_subnet_cidr_block
    availability_zone = var.aws_region
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

resource "aws_nat_gateway" "elk_nat_gw" {
    allocation_id = aws_eip.elk_eip.id
    subnet_id = aws_subnet.elk_subnet_public.id
    tags = {
      Name = "${var.vpc_name}-nat-gw"
      Project = var.project
    }
}

resource "aws_eip" "elk_eip" {
    tags = {
      Name = "${var.vpc_name}-eip"
      Project = var.project
    }
}

resource "aws_security_group" "elk_sg" {
    name = "elk-stack-sg"
    vpc_id = aws_vpc.elk_vpc.id
    description = "Security group for elk stack"

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [var.internet_route]
    }

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [var.internet_route]
    }

    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = [var.internet_route]
    }

    ingress {
        from_port = 5601
        to_port = 5601
        protocol = "tcp"
        cidr_blocks = [var.internet_route]
    }

    ingress {
        from_port = 9200
        to_port = 9200
        protocol = "tcp"
        cidr_blocks = [var.internet_route]
    }

    ingress {
        from_port = 5044
        to_port = 5044
        protocol = "tcp"
        cidr_blocks = [var.internet_route]
    }

    ingress {
        from_port = 9600
        to_port = 9600
        protocol = "tcp"
        cidr_blocks = [var.internet_route]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [var.internet_route]
    }
}


