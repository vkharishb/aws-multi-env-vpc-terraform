variable "name" {
  type = string
}

variable "nat_mode" {
  description = "Either 'single' (1 shared NAT, cheaper) or 'per_az' (1 NAT per AZ, highly available)"
  type        = string

  validation {
    condition     = contains(["single", "per_az"], var.nat_mode)
    error_message = "nat_mode must be either 'single' or 'per_az'."
  }
}

variable "azs" {
  type = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (one per AZ, same order as var.azs) to launch NAT gateways into"
  type        = list(string)
}

variable "internet_gateway_id" {
  description = "IGW ID - kept as an explicit input so the caller wires the dependency correctly even though it isn't referenced directly"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
