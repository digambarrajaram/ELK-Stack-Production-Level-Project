module "ec2" {
  source           = "./ec2"
  aws_region       = var.aws_region
  instance_type    = var.instance_type
  key_name         = var.key_name
  instance_name    = var.instance_name
  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_id
  igw_id           = module.vpc.igw_id
  elk_sg_id        = module.vpc.elk_sg_id
  project          = var.project
  project_repo     = var.project_repo
  elastic_password = var.elastic_password
  kibana_password  = var.kibana_password
 }

module "vpc" {
  source                   = "./vpc"
  aws_region               = var.aws_region
  cidr_block               = var.cidr_block
  vpc_name                 = var.vpc_name
  project                  = var.project
  public_subnet_cidr_block = var.public_subnet_cidr_block
  internet_route           = var.internet_route
  az                       = var.az
}
