variable "name" {
  type = string
}

variable "ami_id" {
  description = "Custom AMI ID. Leave empty (\"\") to auto-select the latest Amazon Linux 2023 AMI."
  type        = string
  default     = ""
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "root_volume_size" {
  type    = number
  default = 20
}

variable "app_sg_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "target_group_arn" {
  type = string
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "cpu_target_value" {
  description = "Target average CPU utilization (%) for the scaling policy"
  type        = number
  default     = 60
}

variable "tags" {
  type    = map(string)
  default = {}
}
