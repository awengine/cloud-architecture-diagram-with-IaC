terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.7"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "${var.aws_region}"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "${var.vpc_cidr}"
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
  vpc_id = aws_vpc.main.id
  count = length(var.public_subnets_cidr)
  cidr_block = element(var.private_subnets_cidr, count.index)
  availability_zone = element(var.availability_zone, count.index)
  tags = {
    "Name" = "public subnet"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnet" {
  vpc_id = aws_vpc.main.id
  count = length(var.private_subnets_cidr)
  cidr_block = element(var.public_subnets_cidr, count.index)
  availability_zone = element(var.availability_zone, count.index)
  tags = {
    "Name" = "private subnet"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public_RT" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "${var.the_internet_cidr}"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Route Table Association with IGW
resource "aws_route_table_association" "RT_association" {
  count = length(var.public_subnets_cidr)
  subnet_id = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public_RT.id
}

# Key Pair
resource "aws_key_pair" "wordpress-key" {
  key_name   = "wordpress-key"
  public_key = file("${var.public_key}")
}

# Security Groups
resource "aws_security_group" "ec2" {
  name        = "ec2"
  vpc_id      = aws_vpc.main.id
  ingress {
    description      = "HTTP from the internet"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["${var.the_internet_cidr}"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["${var.the_internet_cidr}"]
  }

  tags = {
    Name = "ec2"
  }
}

# EC2 Wordpress Server
resource "aws_instance" "wordpress" {
  ami           = "${var.image}"
  instance_type = "t2.micro"
  key_name = aws_key_pair.wordpress-key.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id = element(aws_subnet.public_subnet.*.id, 0)
  associate_public_ip_address = true
  root_block_device {
    volume_size = 10
    delete_on_termination = true
    encrypted = true
  }
  user_data = <<EOF
  #!/bin/bash
  sudo apt update
  sudo apt upgrade -y
  EOF
  tags = {
    "Name" = "wordpress server"
  }
}

# S3
resource "aws_s3_bucket" "static-assets" {
  bucket = "wpstorage-static-assets"
  tags = {
    Name        = "wpstorage-static-assets"
  }
}

resource "aws_s3_bucket_acl" "static-assets-acl" {
  bucket = aws_s3_bucket.static-assets.id
  acl    = "private"
}