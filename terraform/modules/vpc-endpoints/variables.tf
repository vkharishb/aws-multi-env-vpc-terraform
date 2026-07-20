variable "name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "private_route_table_ids" {
  type = list(string)
}

variable "vpc_endpoints_sg_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
