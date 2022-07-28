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

# Key Pair for EC2
# the public key to put into EC2 during launch; keep the private key to access the EC2 after launch
resource "aws_key_pair" "wordpress-key" {
  key_name   = "wordpress-key"
  public_key = file("${var.public_key}")
}

# EC2 - Wordpress Server
resource "aws_instance" "wordpress" {
  count                       = 2  // launch this number of EC2 instances
  ami                         = "${var.image}"
  instance_type               = "t2.micro"  // free-tier
  key_name                    = aws_key_pair.wordpress-key.id
  vpc_security_group_ids      = [aws_security_group.ec2-wordpress.id]
  subnet_id                   = element(aws_subnet.public_subnet.*.id, 0)
  associate_public_ip_address = true
  root_block_device {
    volume_size           = 10  // gb
    delete_on_termination = true
    encrypted             = true  // automatically use the aws managed encryption key 'aws/ebs' in KMS
  }

  # the firstboot script during launch
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
  internal           = false // public-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-wordpress.id]  // which port open to the internet is specified in the security group
  subnets            = [for subnet in aws_subnet.public_subnet : subnet.id]
  tags = {
    Name = "alb-wordpress"
  }
}

resource "aws_lb_target_group" "alb-wordpress-tg" {
  name     = "alb-wordpress-tg"
  port     = 80  // open to the alb
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
  image_id      = "${var.image}"
  instance_type = "t2.micro"
  lifecycle {
    create_before_destroy = true  // create new EC2 before destroy old ones
  }
}

resource "aws_autoscaling_group" "asg-wordpress" {
  name                      = "asg-wordpress"
  max_size                  = 3  // the numbers of EC2 within the group
  min_size                  = 2
  health_check_grace_period = 300  // seconds; the time given to newly launched EC2 for initialization before considering it unhealthy
  health_check_type         = "ELB"
  launch_configuration      = aws_launch_configuration.lc-wordpress.name
  vpc_zone_identifier       = [for subnet in aws_subnet.public_subnet : subnet.id]
  timeouts {
    delete = "15m"  // gives terraform 15 minutes to destroy the asg if requested
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "asg-policy-wordpress" {
  name                   = "asg-policy-wordpress"
  scaling_adjustment     = 2  // desired capacity - must be equal or greater than the min_size
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
  # grant permissions to the wordpress ec2 to read/write the bucket
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
  allocated_storage       = 20  // gb
  storage_type            = "gp2"
  engine                  = "mysql"
  engine_version          = "8.0.27"
  instance_class          = "db.t3.micro"  // free-tier
  multi_az                = true
  name                    = "RDSmysql"
  username                = "wordpressAdmin"
  password                = "${var.rds_mysql_password}"
  db_subnet_group_name    = "subnet-group-mysql"
  parameter_group_name    = "default.mysql8.0"
  option_group_name       = "default:mysql-8-0"
  backup_retention_period = 7  // days
  backup_window           = "13:00-14:00"  // daily auto-backup by rds
  maintenance_window      = "Sat:00:00-Sat:03:00"  // weekly
  vpc_security_group_ids  = [aws_security_group.mysql.id]
  tags = {
    Name = "RDSmysql"
  }
  skip_final_snapshot = true  // if termination is requested, it won't block the process by asking to take final snapshot
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
  s3_bucket_name = aws_s3_bucket.env-wordpress.bucket  // stores the config logs
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
  # grants awsconfig the permissions to read/write to the bucket
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

# add security policy for all rds instances
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
  # grant permissions to cloudtrail to the bucket
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
      "Action": "s3:*",
      "Resource": "${aws_s3_bucket.trail-wordpress.arn}/AWSLogs/*"
    }
  ]
}
POLICY
}
