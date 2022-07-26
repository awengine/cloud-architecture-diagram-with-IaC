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