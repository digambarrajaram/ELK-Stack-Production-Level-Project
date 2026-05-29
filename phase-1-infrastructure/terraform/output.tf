output "instance_id" {
  value = aws_instance.elk_instance.id
}
output "public_ip" {
  value = aws_instance.elk_instance.public_ip
}
output "private_ip" {
  value = aws_instance.elk_instance.private_ip
}

