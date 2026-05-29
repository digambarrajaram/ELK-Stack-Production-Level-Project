variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type"
}

variable "key_name" {
  type        = string
  default     = "elk-stack-server_keypair"
  description = "EC2 key pair"
}

variable "instance_name" {
  type        = string
  default     = "elk-instance"
  description = "EC2 instance name"
}

variable "aws_region" {
  type        = string
  default     = "ap-south-1"
  description = "AWS Region"
}

variable "project" {
  type        = string
  default     = "elk-stack"
  description = "Project name"
}

variable "internet_route" {
  default     = "0.0.0.0/0"
  description = "Internet route"
}
