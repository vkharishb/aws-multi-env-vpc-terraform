variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "app_port" {
  type    = number
  default = 80
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. Leave empty (\"\") to run HTTP-only (e.g. for dev)."
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  description = "Set true for prod to prevent accidental `terraform destroy` of the ALB"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
