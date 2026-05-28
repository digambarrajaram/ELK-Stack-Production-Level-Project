variable "instance_type" {
    type = string
    default = "t3.medium"
    description = "EC2 instance type" 
}

variable "key_name" {
    type = string
    default = "elk-stack-server_keypair"
    description = "EC2 key pair"
}

variable "instance_name" {
    type = string
    default = "elk-instance"
    description = "EC2 instance name"
}

variable "aws_region" { 
    type = string
    default = "ap-south-1" 
    description = "AWS Region"
     }
variable "cidr_block" { 
    type = string
    default = "10.0.0.0/16" 
    description = "cidr_block"
    }
variable "vpc_name" { 
    type = string
    default = "elk-vpc" 
    description = "VPC name"
     }
variable "project" { 
    type = string
    default = "elk-stack" 
    description = "Project name"
     }
variable "public_subnet_cidr_block" { 
    type = string
    default = "10.0.1.0/24" 
    description = "Public subnet CIDR block"
     }
variable "private_subnet_cidr_block" { 
    type = string
    default = "10.0.2.0/24" 
    description = "Private subnet CIDR block"
     }

variable "internet_route" {
    default = "0.0.0.0/0"
    description = "Internet route"
}
