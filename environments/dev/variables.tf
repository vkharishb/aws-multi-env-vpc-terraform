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
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "nat_mode" {
  description = "'single' for cost-optimized dev environments"
  type        = string
  default     = "single"
}

variable "app_port" {
  type    = number
  default = 80
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 1
}

variable "asg_max_size" {
  type    = number
  default = 2
}

variable "asg_desired_capacity" {
  type    = number
  default = 1
}

variable "certificate_arn" {
  description = "Leave empty for HTTP-only in dev"
  type        = string
  default     = ""
}
