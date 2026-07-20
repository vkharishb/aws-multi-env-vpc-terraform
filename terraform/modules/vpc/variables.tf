variable "name" {
  description = "Name prefix for all resources created by this module (e.g. 'dev', 'prod')"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "List of Availability Zones to spread subnets across, e.g. [\"ap-south-1a\", \"ap-south-1b\"]"
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least 2 Availability Zones are required for high availability."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets - must have exactly one entry per AZ, in the same order as var.azs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets - must have exactly one entry per AZ, in the same order as var.azs"
  type        = list(string)
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
