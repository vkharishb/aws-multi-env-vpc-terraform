variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_port" {
  description = "TCP port the application listens on inside the instances"
  type        = number
  default     = 80
}

variable "tags" {
  type    = map(string)
  default = {}
}
