aws_region   = "ap-south-1"
project_name = "multienv-vpc"

vpc_cidr             = "10.1.0.0/16"
azs                  = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]

nat_mode = "per_az" # HA - no single point of failure

instance_type         = "t3.small"
asg_min_size           = 3
asg_max_size           = 6
asg_desired_capacity   = 3

certificate_arn = "" # set your ACM cert ARN here to enable HTTPS
