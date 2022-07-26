variable "aws_region" {
  default = "ap-southeast-1"
}

# VPC
variable "vpc_cidr" {
  default = "10.0.0.0/22"
}

variable "the_internet_cidr" {
  default = "0.0.0.0/0"
}

variable "public_subnets_cidr" {
  type    = list(any)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnets_cidr" {
  type    = list(any)
  default = ["10.0.2.0/24", "10.0.3.0/24"]
}

variable "availability_zone" {
  type    = list(any)
  default = ["ap-southeast-1a", "ap-southeast-1b"]
}

# EC2
# Create a key-pair yourself and supply the public key
variable "public_key" {
  default = "./wordpress-key.pub"
}

variable "image" {
  default = "ami-000965411c503c8ed"
}

# RDS
variable "rds_mysql_password" {
  default = "fillYourPassword"
}
