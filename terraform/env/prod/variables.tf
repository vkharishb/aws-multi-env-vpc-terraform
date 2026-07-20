variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "multienv-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
}

variable "nat_mode" {
  description = "'per_az' for prod - one NAT Gateway per AZ so no single point of failure"
  type        = string
  default     = "per_az"
}

variable "app_port" {
  type    = number
  default = 80
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "asg_min_size" {
  type    = number
  default = 3
}

variable "asg_max_size" {
  type    = number
  default = 6
}

variable "asg_desired_capacity" {
  type    = number
  default = 3
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS - strongly recommended for prod"
  type        = string
  default     = ""
}
