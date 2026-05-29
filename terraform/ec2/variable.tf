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


variable "igw_id" {
    description = "Internet Gateway ID" 
}


variable "project" {
    description = "Project name"
}

variable "elk_sg_id" {
    description = "elk security group id"
}
variable "project_repo" {
    description = "Project repo"
}

variable "elastic_password" {
  description = "Elasticsearch superuser password"
}

variable "kibana_password" {
  description = "Kibana system user password"
}