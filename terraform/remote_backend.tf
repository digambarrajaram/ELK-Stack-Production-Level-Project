terraform {
  backend "s3" {
    bucket       = "elk-stack-remote-tf-state"
    key          = "elk-stack/terraform.tfstate"
    region       = "ap-south-1" # Mumbai region
    encrypt      = true
    use_lockfile = true         
  }
}
