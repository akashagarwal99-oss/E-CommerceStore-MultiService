output "vpc_id" {
  description = "The ID of the ecommerce VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "The ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "The ID of the private subnet"
  value       = aws_subnet.private.id
}

output "nat_gateway_id" {
  description = "The ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "frontend_instance_id" {
  description = "The ID of the frontend instance"
  value       = aws_instance.frontend.id
}

output "frontend_public_ip" {
  description = "Public IP address of the frontend EC2 instance"
  value       = aws_instance.frontend.public_ip
}

output "frontend_public_dns" {
  description = "Public DNS name of the frontend EC2 instance"
  value       = aws_instance.frontend.public_dns
}