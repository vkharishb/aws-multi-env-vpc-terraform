##############################################################################
# VPC ENDPOINTS MODULE
#
# ACCESS MANAGEMENT STRATEGY:
# Instances live in private subnets with no public IP and no inbound SSH.
# Instead of a bastion host (extra attack surface, another thing to patch),
# engineers connect via AWS Systems Manager Session Manager, which is:
#   - IAM-authenticated (no SSH keys to manage/rotate/leak)
#   - Fully audit-logged (every session can be logged to S3/CloudWatch)
#   - No inbound security group rule required at all
#
# Interface endpoints below let SSM traffic reach the instances entirely
# over AWS's private network, WITHOUT needing a route through the NAT
# Gateway/Internet - tighter security and it also shaves a bit of NAT data
# processing cost.
#
# S3 gateway endpoint (free, no hourly cost) lets instances pull from S3
# (e.g. app artifacts, SSM agent updates) without traversing the NAT Gateway.
##############################################################################

locals {
  interface_endpoint_services = [
    "ssm",
    "ssmmessages",
    "ec2messages",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(local.interface_endpoint_services)
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.vpc_endpoints_sg_id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpce-${each.value}"
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(var.tags, {
    Name = "${var.name}-vpce-s3"
  })
}
