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
  region = var.aws_region
}

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

# Key Pair
resource "aws_key_pair" "wordpress-key" {
  key_name   = "wordpress-key"
  public_key = file("${var.public_key}")
}

# Security Groups
resource "aws_security_group" "mysql" {
  name   = "mysql"
  vpc_id = aws_vpc.main.id
  ingress {
    description     = "Access from EC2 wordpress"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2-wordpress.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.the_internet_cidr}"]
  }
  tags = {
    Name = "mysql"
  }
}

resource "aws_security_group" "ec2-wordpress" {
  name   = "ec2-wordpress"
  vpc_id = aws_vpc.main.id
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb-wordpress.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.the_internet_cidr}"]
  }
  tags = {
    Name = "ec2-wordpress"
  }
}

resource "aws_security_group" "alb-wordpress" {
  name   = "alb-wordpress"
  vpc_id = aws_vpc.main.id
  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.the_internet_cidr}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.the_internet_cidr}"]
  }
  tags = {
    Name = "alb-wordpress"
  }
}

# EC2 Wordpress Server
resource "aws_instance" "wordpress" {
  count                       = 2
  ami                         = var.image
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.wordpress-key.id
  vpc_security_group_ids      = [aws_security_group.ec2-wordpress.id]
  subnet_id                   = element(aws_subnet.public_subnet.*.id, 0)
  associate_public_ip_address = true
  root_block_device {
    volume_size           = 10
    delete_on_termination = true
    encrypted             = true
  }
  user_data = <<EOF
  #!/bin/bash
  sudo apt update
  sudo apt upgrade -y
  EOF
  tags = {
    "Name" = "wordpress server",
    "Backup" = "true"
  }
}

# ALB
resource "aws_lb" "alb-wordpress" {
  name               = "alb-wordpress"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-wordpress.id]
  subnets            = [for subnet in aws_subnet.public_subnet : subnet.id]
  tags = {
    Name = "alb-wordpress"
  }
}

resource "aws_lb_target_group" "alb-wordpress-tg" {
  name     = "alb-wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "alb-wordpress" {
  count            = length(aws_instance.wordpress)
  target_group_arn = aws_lb_target_group.alb-wordpress-tg.arn
  target_id        = aws_instance.wordpress[count.index].id
  port             = 80
}

resource "aws_lb_listener" "alb-wordpress" {
  load_balancer_arn = aws_lb.alb-wordpress.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-wordpress-tg.arn
  }
}

# Autoscaling Group
resource "aws_launch_configuration" "lc-wordpress" {
  name_prefix   = "terraform-lc-"
  key_name      = aws_key_pair.wordpress-key.id
  image_id      = var.image
  instance_type = "t2.micro"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "asg-wordpress" {
  name                      = "asg-wordpress"
  max_size                  = 2
  min_size                  = 0
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.lc-wordpress.name
  vpc_zone_identifier       = [for subnet in aws_subnet.public_subnet : subnet.id]
  timeouts {
    delete = "15m"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "asg-policy-wordpress" {
  name                   = "asg-policy-wordpress"
  scaling_adjustment     = 2
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg-wordpress.name
}

resource "aws_autoscaling_attachment" "asg-attachment-alb" {
  autoscaling_group_name = aws_autoscaling_group.asg-wordpress.id
  alb_target_group_arn   = aws_lb_target_group.alb-wordpress-tg.arn
}

# S3
resource "aws_s3_bucket" "static-assets" {
  bucket = "wpstorage-static-assets"
  tags = {
    Name = "wpstorage-static-assets"
  }
}

resource "aws_s3_bucket_policy" "policy-static-assets" {
  bucket = aws_s3_bucket.static-assets.id
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSS3Access",
            "Effect": "Allow",
            "Principal": {
              "Service": "ec2.amazonaws.com"
            },
            "Action": "s3:*",
            "Resource": [
              "${aws_s3_bucket.static-assets.arn}",
              "${aws_s3_bucket.static-assets.arn}/*"
            ]
        }
    ]
}
POLICY
}

# RDS
resource "aws_db_instance" "rds-mysql" {
  allocated_storage       = 20
  storage_type            = "gp2"
  engine                  = "mysql"
  engine_version          = "8.0.27"
  instance_class          = "db.t3.micro"
  multi_az                = true
  name                    = "RDSmysql"
  username                = "wordpressAdmin"
  password                = var.rds_mysql_password
  db_subnet_group_name    = "subnet-group-mysql"
  parameter_group_name    = "default.mysql8.0"
  option_group_name       = "default:mysql-8-0"
  backup_retention_period = 7
  backup_window           = "13:00-14:00"
  maintenance_window      = "Sat:00:00-Sat:03:00"
  vpc_security_group_ids  = [aws_security_group.mysql.id]
  tags = {
    Name = "RDSmysql"
  }
}

resource "aws_db_subnet_group" "subnet-group-mysql" {
  name       = "subnet-group-mysql"
  subnet_ids = [for subnet in aws_subnet.private_subnet : subnet.id]
  tags = {
    Name = "subnet-group-mysql"
  }
}

# IAM
resource "aws_iam_user_group_membership" "member-developers" {
  user = aws_iam_user.wp-developer.name
  groups = [
    aws_iam_group.developers.name,
  ]
}

resource "aws_iam_group" "developers" {
  name = "developers"
  path = "/users/"
}

resource "aws_iam_policy" "developers" {
  name        = "policy-developers"
  description = "IAM policy for developers group"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "rds:*",
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_group_policy_attachment" "policy-attach" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.developers.arn
}

resource "aws_iam_user" "wp-developer" {
  name = "wp-developer"
  tags = {
    Name = "wp-developer"
  }
}

# Config
resource "aws_config_delivery_channel" "env-wordpress" {
  name           = "env-wordpress"
  s3_bucket_name = aws_s3_bucket.env-wordpress.bucket
  depends_on     = [aws_config_configuration_recorder.env-wordpress]
}

resource "aws_s3_bucket" "env-wordpress" {
  bucket        = "env-wordpress-awsconfig"
  force_destroy = true
}

resource "aws_config_configuration_recorder" "env-wordpress" {
  name     = "env-wordpress"
  role_arn = aws_iam_role.role-awsconfig.arn
}

resource "aws_iam_role" "role-awsconfig" {
  name               = "role-awsconfig"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "config.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "policy-awsconfig" {
  name = "policy-awsconfig"
  role = aws_iam_role.role-awsconfig.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.env-wordpress.arn}",
        "${aws_s3_bucket.env-wordpress.arn}/*"
      ]
    }
  ]
}
POLICY
}

resource "aws_config_conformance_pack" "config_conformance_rds" {
  name          = "configRDS"
  template_body = <<EOT
Resources:
  DbInstanceBackupEnabled:
    Properties:
      ConfigRuleName: db-instance-backup-enabled
      Source:
        Owner: AWS
        SourceIdentifier: DB_INSTANCE_BACKUP_ENABLED
    Type: AWS::Config::ConfigRule
EOT
  depends_on    = [aws_config_configuration_recorder.env-wordpress]
}

# Cloudtrail - single region
resource "aws_cloudtrail" "env-wordpress" {
  name                          = "tf-trail-env-wordpress"
  s3_bucket_name                = aws_s3_bucket.trail-wordpress.id
  include_global_service_events = true
}

resource "aws_s3_bucket" "trail-wordpress" {
  bucket        = "tf-trail-wordpress"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "policy-trail-wordpress" {
  bucket = aws_s3_bucket.trail-wordpress.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "${aws_s3_bucket.trail-wordpress.arn}"
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "${aws_s3_bucket.trail-wordpress.arn}/*"
    }
  ]
}
POLICY
}