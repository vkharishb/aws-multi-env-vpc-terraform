output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "app_sg_id" {
  value = aws_security_group.app.id
}

output "vpc_endpoints_sg_id" {
  value = aws_security_group.vpc_endpoints.id
}
