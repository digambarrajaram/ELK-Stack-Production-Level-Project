variable "aws_region" {
    description = "AWS Region"
}

variable "instance_type" {
    description = "EC2 instance type" 
}

variable "key_name" {
    description = "EC2 key pair"
}

variable "instance_name" {
    description = "EC2 instance name"
}

variable "vpc_id" {
    description = "VPC ID"
}

variable "public_subnet_id" {
    description = "Public subnet ID"
}

variable "private_subnet_id" {
    description = "Private subnet ID"
}

variable "igw_id" {
    description = "Internet Gateway ID" 
}

variable "nat_gw_id" {
    description = "NAT Gateway ID"
}

variable "eip_id" {
    description = "EIP ID"
}

variable "project" {
    description = "Project name"
}

variable "elk_sg_id" {
    description = "elk security group id"
}