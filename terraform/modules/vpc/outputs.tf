output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs, ordered to match var.azs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs, ordered to match var.azs"
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs, ordered to match var.azs (one per AZ)"
  value       = aws_route_table.private[*].id
}

output "azs" {
  value = var.azs
}
