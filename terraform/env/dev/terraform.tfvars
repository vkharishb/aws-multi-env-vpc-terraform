aws_region   = "ap-south-1"
project_name = "multienv-vpc"

vpc_cidr             = "10.0.0.0/16"
azs                  = ["ap-south-1a", "ap-south-1b"]
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

nat_mode = "single" # cost-optimized for dev

instance_type         = "t3.micro"
asg_min_size           = 1
asg_max_size           = 2
asg_desired_capacity   = 1

certificate_arn = "" # HTTP-only in dev
