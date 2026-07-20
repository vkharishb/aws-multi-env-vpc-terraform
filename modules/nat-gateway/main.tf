##############################################################################
# NAT GATEWAY MODULE
#
# Supports two modes via var.nat_mode:
#   "single"  - one NAT Gateway total (cheapest, but a single point of
#               failure - fine for dev/sandbox environments)
#   "per_az"  - one NAT Gateway per AZ (highly available - if one AZ goes
#               down, the other AZs' private subnets keep working)
##############################################################################

locals {
  # In "single" mode we still only create 1 NAT, placed in the first public subnet.
  # In "per_az" mode we create len(azs) NAT gateways, one per public subnet.
  nat_count = var.nat_mode == "single" ? 1 : length(var.azs)
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = merge(var.tags, {
    Name = var.nat_mode == "single" ? "${var.name}-nat-eip" : "${var.name}-nat-eip-${var.azs[count.index]}"
  })
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = var.public_subnet_ids[count.index]

  tags = merge(var.tags, {
    Name = var.nat_mode == "single" ? "${var.name}-nat" : "${var.name}-nat-${var.azs[count.index]}"
  })
}
