##############################################################################
# SECURITY GROUPS MODULE
#
# Chain of trust (least privilege):
#   Internet -> ALB SG (80/443 from 0.0.0.0/0)
#   ALB SG   -> App SG (app_port, source = ALB SG ONLY, not 0.0.0.0/0)
#   App SG   -> Endpoints SG (443, source = App SG ONLY) for SSM/EC2 API calls
#
# Nothing in this stack accepts SSH (port 22) from anywhere. Instance access
# is via AWS Systems Manager Session Manager (see modules/asg + modules/vpc-endpoints).
##############################################################################

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-sg-"
  description = "Allow inbound HTTP/HTTPS from the internet to the ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "ALB to app instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-alb-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app" {
  name_prefix = "${var.name}-app-sg-"
  description = "Allow inbound app traffic ONLY from the ALB security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port from ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound (updates, SSM, package installs via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-app-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name}-vpce-sg-"
  description = "Allow HTTPS from app instances to interface VPC endpoints (SSM, etc.)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from app instances"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-vpce-sg" })

  lifecycle {
    create_before_destroy = true
  }
}
