output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "alb_dns_name" {
  description = "Point your browser (or a Route53 CNAME) here to reach the app"
  value       = module.alb.alb_dns_name
}

output "nat_gateway_public_ips" {
  value = module.nat_gateway.nat_gateway_public_ips
}

output "asg_name" {
  value = module.asg.asg_name
}
