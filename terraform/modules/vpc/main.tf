##############################################################################
# VPC MODULE
# Creates: VPC, Internet Gateway, public subnets, private subnets
#          (one of each per AZ), public route table, and one private route
#          table per AZ (so each AZ's NAT gateway can be wired independently
#          by the caller - keeps this module NAT-agnostic).
##############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

# ---------------------------------------------------------------------------
# Public subnets - one per AZ
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true # instances here (e.g. NAT, ALB ENIs) get a public IP

  tags = merge(var.tags, {
    Name                     = "${var.name}-public-${var.azs[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1" # harmless/no-op outside EKS, useful if this VPC is reused for a cluster later
  })
}

# ---------------------------------------------------------------------------
# Private subnets - one per AZ
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name                              = "${var.name}-private-${var.azs[count.index]}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# ---------------------------------------------------------------------------
# Public route table - single table shared by all public subnets, routes
# 0.0.0.0/0 straight to the Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private route tables - ONE PER AZ. The 0.0.0.0/0 -> NAT route is added by
# the root module (environments/dev|prod) once it knows the NAT gateway IDs
# from the nat-gateway module. This keeps the VPC module reusable regardless
# of whether NAT is "single shared" or "one per AZ".
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-private-rt-${var.azs[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
