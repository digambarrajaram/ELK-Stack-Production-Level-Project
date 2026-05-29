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
    vpc_security_group_ids = [var.elk_sg_id]
    subnet_id = var.public_subnet_id

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

    tags = {
      Name = var.instance_name
      Project = var.project
    }

  user_data_base64 = base64encode(templatefile("${path.module}/user-data.sh", {
    project_repo = var.project_repo
  }))
}
