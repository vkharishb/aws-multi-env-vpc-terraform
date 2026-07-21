locals {
  name = "${var.project_name}-prod"
  tags = {
    Environment = "prod"
    Project     = var.project_name
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  tags                 = local.tags
}

module "nat_gateway" {
  source = "../../modules/nat-gateway"

  name                = local.name
  nat_mode            = var.nat_mode
  azs                 = var.azs
  public_subnet_ids   = module.vpc.public_subnet_ids
  internet_gateway_id = module.vpc.internet_gateway_id
  tags                = local.tags
}

resource "aws_route" "private_nat_access" {
  count                  = length(var.azs)
  route_table_id         = module.vpc.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = module.nat_gateway.nat_gateway_ids[var.azs[count.index]]
}

# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------
module "security_groups" {
  source = "../../modules/security-groups"

  name     = local.name
  vpc_id   = module.vpc.vpc_id
  app_port = var.app_port
  tags     = local.tags
}

module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  name                    = local.name
  aws_region              = var.aws_region
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids
  vpc_endpoints_sg_id     = module.security_groups.vpc_endpoints_sg_id
  tags                    = local.tags
}

# ---------------------------------------------------------------------------
# Load Balancer + Compute
# ---------------------------------------------------------------------------
module "alb" {
  source = "../../modules/alb"

  name                       = local.name
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  alb_sg_id                  = module.security_groups.alb_sg_id
  app_port                   = var.app_port
  certificate_arn            = var.certificate_arn
  enable_deletion_protection = true # prod: block accidental `terraform destroy` of the ALB
  tags                       = local.tags
}

module "asg" {
  source = "../../modules/asg"

  name               = local.name
  aws_region         = var.aws_region
  instance_type      = var.instance_type
  app_sg_id          = module.security_groups.app_sg_id
  private_subnet_ids = module.vpc.private_subnet_ids
  target_group_arn   = module.alb.target_group_arn
  min_size           = var.asg_min_size
  max_size           = var.asg_max_size
  desired_capacity   = var.asg_desired_capacity
  tags               = local.tags
}
