output "nat_gateway_ids" {
  description = "Map of AZ -> NAT Gateway ID. In 'single' mode every AZ maps to the same NAT Gateway ID."
  value = var.nat_mode == "single" ? {
    for az in var.azs : az => aws_nat_gateway.this[0].id
    } : {
    for idx, az in var.azs : az => aws_nat_gateway.this[idx].id
  }
}

output "nat_gateway_public_ips" {
  value = aws_eip.nat[*].public_ip
}
