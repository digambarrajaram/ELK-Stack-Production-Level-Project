output "vpc_id" {
    value = aws_vpc.elk_vpc.id
}

output "public_subnet_id" {
    value = aws_subnet.elk_subnet_public.id
}

output "igw_id" {
    value = aws_internet_gateway.elk_igw.id
}

output "nat_gw_id" {
    value = aws_nat_gateway.elk_nat_gw.id
}

output "eip_id" {
    value = aws_eip.elk_eip.id
}

output "elk_sg_id" {
    value = aws_security_group.elk_sg.id
}

output "private_subnet_id" {
    value = aws_subnet.elk_subnet_private.id
}


