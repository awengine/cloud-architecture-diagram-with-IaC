# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    "Name" = "VPC-main"
  }
}

resource "aws_main_route_table_association" "RT_association_vpc" {
  vpc_id         = aws_vpc.main.id
  route_table_id = aws_route_table.public_RT.id
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Public Subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.main.id
  count             = length(var.public_subnets_cidr)
  cidr_block        = element(var.private_subnets_cidr, count.index)
  availability_zone = element(var.availability_zone, count.index)
  tags = {
    "Name" = "public subnet"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main.id
  count             = length(var.private_subnets_cidr)
  cidr_block        = element(var.public_subnets_cidr, count.index)
  availability_zone = element(var.availability_zone, count.index)
  tags = {
    "Name" = "private subnet"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public_RT" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = var.the_internet_cidr
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Route Table Association with IGW
resource "aws_route_table_association" "RT_association" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public_RT.id
}