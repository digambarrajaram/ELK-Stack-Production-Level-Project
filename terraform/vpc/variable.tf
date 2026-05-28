variable "aws_region" { 
    description = "AWS Region"
     }
variable "cidr_block" { 
    description = "cidr_block"
    }
variable "vpc_name" { 
    description = "elk-vpc"
     }
variable "project" { 
    description = "Project name"
     }
variable "public_subnet_cidr_block" { 
    description = "public_subnet_cidr_block"
     }
variable "private_subnet_cidr_block" { 
    description = "private_subnet_cidr_block"   
     }

variable "internet_route" {
    description = "Internet route"
}
