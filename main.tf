resource "aws_instance" "default" {
  instance_type               = var.instance_type
  associate_public_ip_address = false
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = concat(var.security_group_ids, [aws_security_group.default.id])
  ami                         = data.aws_ami.amazon_linux_2023_kernel_6_1.id
  iam_instance_profile        = aws_iam_instance_profile.default_instance.name
  user_data = templatefile("${path.module}/user-data.template", {
    docker_compose  = var.docker_compose
    public_ssh_keys = var.public_ssh_keys
  })
  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }
  tags = {
    Name = "${var.project}-${var.environment}-${var.name}"
  }
}

data "aws_ami" "amazon_linux_2023_kernel_6_1" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.8.20250818.0-kernel-6.12-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

}

# Attach the EBS volume to the instance
resource "aws_volume_attachment" "default_data" {
  device_name = "/dev/xvdf" # Device name as it will appear to the instance
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.default.id
}

data "aws_iam_policy_document" "default_instance" {
  statement {
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssm:ListInstanceAssociations",
      "ssm:DescribeInstanceInformation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:SendCommand",
      "ssm:ListCommands",
      "ssm:ListCommandInvocations",
      "ssm:GetCommandInvocation",
      "ssm:DescribeDocument",
      "ssm:GetDocument",
      "ssm:DescribeAssociation",
      "ssm:ListAssociations",
      "ssm:ListDocuments",
      "ssm:DescribeInstancePatches",
      "ssm:DescribeInstancePatchStates",
      "ssm:DescribeInstancePatchStatesForPatchGroup",
      "ssm:GetParametersByPath",
      "ssm:GetParameters",
      "ec2messages:GetEndpoint",
      "ec2messages:DeleteMessage",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "states:SendTaskSuccess"
    ]

    resources = [
      "*"
    ]
  }
}

data "aws_iam_policy_document" "default_instance_assume_role" {

  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role_policy" "default_instance" {
  policy = data.aws_iam_policy_document.default_instance.json
  role   = aws_iam_role.default_instance.id
}

resource "aws_iam_role" "default_instance" {
  name               = "${var.project}-${var.environment}-${var.name}"
  assume_role_policy = data.aws_iam_policy_document.default_instance_assume_role.json
}

resource "aws_iam_instance_profile" "default_instance" {
  name = "${var.project}-${var.environment}-${var.name}-instance-profile"
  role = aws_iam_role.default_instance.name
}

resource "aws_security_group" "default" {
  description = "Controls access to the ${var.name}"
  vpc_id      = var.vpc_id
  name        = "${var.project}-${var.environment}-${var.name}"
}

resource "aws_security_group_rule" "default_ssh" {
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.default.id
  to_port           = 22
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_security_group_rule" "default_http" {
  from_port         = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.default.id
  to_port           = 80
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  size              = 10
  iops              = 3000
  type              = "gp3"

  tags = {
    Name = "${var.project}-${var.environment}-data"
  }
  final_snapshot = true
}

data "aws_iam_policy_document" "dlm" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "dlm_lifecycle_role" {
  name               = "${var.project}-${var.environment}-dlm"
  assume_role_policy = data.aws_iam_policy_document.dlm.json
}

data "aws_iam_policy_document" "dlm_lifecycle" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateSnapshot",
      "ec2:CreateSnapshots",
      "ec2:DeleteSnapshot",
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
    ]

    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*::snapshot/*"]
  }
}

resource "aws_iam_role_policy" "dlm_lifecycle" {
  name   = "dlm-lifecycle-policy"
  role   = aws_iam_role.dlm_lifecycle_role.id
  policy = data.aws_iam_policy_document.dlm_lifecycle.json
}

resource "aws_dlm_lifecycle_policy" "default" {
  description        = "example DLM lifecycle policy"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "2 weeks of daily snapshots"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["23:45"]
      }

      retain_rule {
        count = 14
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
      }

      copy_tags = false
    }

    target_tags = {
      Name = "${var.project}-${var.environment}-data"
    }
  }
}
