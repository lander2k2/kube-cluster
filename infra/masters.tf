variable "master0_ami" {}
variable "master_ami" {}
variable "master_type" {
  default = "m4.xlarge"
}
variable "master_disk_size" {
  default = 100
}

resource "aws_iam_role" "master_role" {
    name = "master_role"

    assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "master_policy" {
    name = "master_policy"
    role = "${aws_iam_role.master_role.id}"

    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:Describe*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ec2:AttachVolume",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ec2:DetachVolume",
      "Resource": "*"
    },
    {
      "Action": "elasticloadbalancing:*",
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:BatchGetImage"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action" : [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::*",
      "Effect": "Allow"
    },
    {
      "Action" : [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "master_profile" {
  name = "k8s_master_profile"
  role = "${aws_iam_role.master_role.name}"
}

resource "aws_security_group" "master_sg" {
  name   = "master_sg"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }
  ingress {
    from_port = 10251
    to_port   = 10252
    protocol  = "TCP"
    self      = "true"
  }
  ingress {
    from_port   = 10255
    to_port     = 10255
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }
  ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "4"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }

  tags {
    Name = "heptio-master"
    vendor = "heptio"
  }
}

resource "aws_security_group" "master_lb_sg" {
  name   = "master_lb_sg"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "TCP"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${data.aws_vpc.existing.cidr_block}"]
  }

  tags {
    Name = "heptio-k8s-api-lb"
    vendor = "heptio"
  }
}

resource "aws_instance" "master0_node" {
  count                  = 1
  ami                    = "${var.master0_ami}"
  instance_type          = "${var.master_type}"
  subnet_id              = "${var.primary_subnet}"
  vpc_security_group_ids = ["${aws_security_group.master_sg.id}"]
  key_name               = "${var.key_name}"
  ebs_optimized          = "true"
  iam_instance_profile   = "${aws_iam_instance_profile.master_profile.name}"
  source_dest_check      = "false"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "${var.master_disk_size}"
    delete_on_termination = "true"
  }

  tags {
    "Name"                       = "heptio-master0"
    "vendor"                     = "heptio"
    "kubernetes.io/cluster/cl01" = "owned"
  }
}

resource "aws_instance" "master_node" {
  count                  = 2
  ami                    = "${var.master_ami}"
  instance_type          = "${var.master_type}"
  subnet_id              = "${var.primary_subnet}"
  vpc_security_group_ids = ["${aws_security_group.master_sg.id}"]
  key_name               = "${var.key_name}"
  ebs_optimized          = "true"
  source_dest_check      = "false"
  iam_instance_profile   = "${aws_iam_instance_profile.master_profile.name}"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "${var.master_disk_size}"
    delete_on_termination = "true"
  }

  tags {
    "Name"                       = "heptio-master"
    "vendor"                     = "heptio"
    "kubernetes.io/cluster/cl01" = "owned"
  }
}

resource "aws_elb" "api_elb" {
  subnets                   = ["${var.primary_subnet}"]
  internal                  = "true"
  instances                 = ["${aws_instance.master0_node.id}", "${aws_instance.master_node.*.id}"]
  security_groups           = ["${aws_security_group.master_lb_sg.id}"]
  cross_zone_load_balancing = "true"

  listener {
    instance_port     = 6443
    instance_protocol = "TCP"
    lb_port           = 6443
    lb_protocol       = "TCP"
  }

  tags {
    Name = "heptio-k8s-api-lb"
    vendor = "heptio"
  }
}

output "master0_ep" {
  value = "${aws_instance.master0_node.private_dns}"
}

output "master0_ip" {
  value = "${aws_instance.master0_node.private_ip}"
}

output "master_ep" {
  value = "${aws_instance.master_node.*.private_dns}"
}

output "master_ip" {
  value = "${aws_instance.master_node.*.private_ip}"
}

output "api_lb_ep" {
  value = "${aws_elb.api_elb.dns_name}"
}

