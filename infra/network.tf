# VPC with public, private app and private DB subnets in 2 AZs (see docs/services.md)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.prefix}-vpc" }
}

locals {
  public_cidrs = ["10.0.0.0/19", "10.0.32.0/19"]
  app_cidrs    = ["10.0.64.0/19", "10.0.96.0/19"]
  db_cidrs     = ["10.0.128.0/19", "10.0.160.0/19"]
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.prefix}-public-${count.index + 1}" }
}

resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.app_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags              = { Name = "${var.prefix}-app-${count.index + 1}" }
}

resource "aws_subnet" "db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.db_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags              = { Name = "${var.prefix}-db-${count.index + 1}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# The design uses one NAT gateway per AZ. The shared class account hit its
# Elastic IP limit, so this demo uses 1 NAT gateway for both app subnets.
locals {
  nat_count = 1
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = { Name = "${var.prefix}-nat-eip-${count.index + 1}" }
}

resource "aws_nat_gateway" "main" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.prefix}-nat-${count.index + 1}" }
  depends_on    = [aws_internet_gateway.main]
}

# each app subnet routes out through the NAT gateway
resource "aws_route_table" "app" {
  count  = 2
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[min(count.index, local.nat_count - 1)].id
  }
  tags = { Name = "${var.prefix}-app-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# DB subnets have no internet route, they use the VPC main route table (local only)
