##############################################################################
# ASG MODULE
# Launch template + Auto Scaling Group running in PRIVATE subnets, attached
# to the ALB's target group. Instances get an IAM instance profile with SSM
# permissions ONLY (no SSH keys, no bastion) - see modules/vpc-endpoints for
# how SSM traffic reaches them privately.
##############################################################################

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

// Region used for templating/user-data if needed. Declared here to fix
// reference to var.aws_region from this module.
variable "aws_region" {
  description = "AWS region where resources are deployed"
  type        = string
}

# ---------------------------------------------------------------------------
# IAM role - SSM only. No SSH keypair is created or referenced anywhere.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "instance" {
  name_prefix = "${var.name}-app-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.name}-app-profile-"
  role        = aws_iam_role.instance.name
}

# ---------------------------------------------------------------------------
# Launch Template
# ---------------------------------------------------------------------------
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-lt-"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  # No key_name set on purpose - access is via SSM Session Manager only.

  iam_instance_profile {
    name = aws_iam_instance_profile.this.name
  }

  vpc_security_group_ids = [var.app_sg_id]

  metadata_options {
    http_tokens                 = "required" # IMDSv2 enforced - blocks SSRF-style credential theft
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    environment = var.name
    aws_region  = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-app" })
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Auto Scaling Group - spans every private subnet passed in (i.e. every AZ)
# ---------------------------------------------------------------------------
resource "aws_autoscaling_group" "this" {
  name_prefix         = "${var.name}-asg-"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.target_group_arn]

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type         = "ELB" # fail out of rotation on ALB health check, not just EC2 status
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  # When the launch template changes (new AMI, new user_data, etc.) roll
  # existing instances automatically instead of leaving them on the old
  # version until they happen to be replaced some other way.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }

  # Spread instances evenly across AZs for real HA, not just "multi-AZ on paper"
  availability_zone_distribution {
    capacity_distribution_strategy = "balanced-best-effort"
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = "${var.name}-app" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Target tracking scaling policy - keeps average CPU near the target by
# adding/removing instances automatically
# ---------------------------------------------------------------------------
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}
