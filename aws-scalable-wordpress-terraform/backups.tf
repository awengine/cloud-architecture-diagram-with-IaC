# AWS Backup
resource "aws_backup_plan" "backup-plan-ec2-daily" {
  name = "backup-plan-ec2-daily"
  rule {
    rule_name         = "backup-rule-ec2-daily"
    target_vault_name = aws_backup_vault.ec2-daily.name
    schedule          = "cron(0 4 * * ? *)"  // 4 a.m. daily
    lifecycle {
      delete_after = 7  // days
    }
    recovery_point_tags = {
      Creator = "aws-backups"
    }
  }
}

resource "aws_backup_vault" "ec2-daily" {
  name = "ec2-daily"
}

resource "aws_iam_role" "role-backup" {
  name               = "role-backup"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["sts:AssumeRole"],
      "Effect": "allow",
      "Principal": {
        "Service": ["backup.amazonaws.com"]
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "role-back-ec2" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"  // aws managed policy to grant permissions to the backup service to back up other services e.g. ec2
  role       = aws_iam_role.role-backup.name
}

resource "aws_backup_selection" "selection-ec2" {
  iam_role_arn = aws_iam_role.role-backup.arn
  name         = "selection-ec2"
  plan_id      = aws_backup_plan.backup-plan-ec2-daily.id
  selection_tag {
    # select only services with this tag to back up
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}