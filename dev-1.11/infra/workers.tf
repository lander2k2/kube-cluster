variable "worker_count" {}
variable "worker_ami" {}
variable "worker_type" {}

resource "aws_iam_role" "worker_role" {
  name = "${var.cluster_name}_worker_role"

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

resource "aws_iam_role_policy" "worker_policy" {
  name = "${var.cluster_name}_worker_policy"
  role = "${aws_iam_role.worker_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:AttachVolume",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:Describe*",
        "ec2:DescribeInstances",
        "ec2:DetachVolume",
        "ec2:CreateRoute",
        "elasticloadbalancing:*"
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
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:AttachNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:DetachNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeInstances",
        "ec2:ModifyNetworkInterfaceAttribute",
        "ec2:ModifyInstanceAttribute",
        "ec2:AssignPrivateIpAddresses"
     ],
     "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "tag:TagResources",
      "Resource": "*"
    },
    {
      "Action" : [
        "ec2:CreateSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:DeleteSecurityGroup",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.cluster_name}_k8s_worker_profile"
  role = "${aws_iam_role.worker_role.name}"
}

resource "aws_security_group" "worker_sg" {
  name   = "worker_sg"
  vpc_id = "${aws_vpc.k8s_cluster.id}"

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "TCP"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 10255
    to_port     = 10255
    protocol    = "TCP"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "TCP"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # calico
  ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "TCP"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "4"
    cidr_blocks = ["10.0.0.0/16"]
  }
  # calico typha
  ingress {
    from_port   = 5473
    to_port     = 5473
    protocol    = "TCP"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${map(
    "Name",                                      "${var.cluster_name}-worker",
    "KubernetesCluster",                         "${var.cluster_name}",
    "kubernetes.io/cluster/${var.cluster_name}", "owned"
  )}"
}

resource "aws_instance" "worker_node" {
  count                       = "${var.worker_count}"
  ami                         = "${var.worker_ami}"
  instance_type               = "${var.worker_type}"
  subnet_id                   = "${aws_subnet.k8s_cluster0.id}"
  vpc_security_group_ids      = ["${aws_security_group.worker_sg.id}"]
  key_name                    = "${var.key_name}"
  associate_public_ip_address = "true"
  depends_on                  = ["aws_internet_gateway.k8s_cluster"]
  iam_instance_profile        = "${aws_iam_instance_profile.worker_profile.name}"
  source_dest_check           = "false"

  tags = "${map(
    "Name",                                      "${var.cluster_name}-worker",
    "KubernetesCluster",                         "${var.cluster_name}",
    "kubernetes.io/cluster/${var.cluster_name}", "owned"
  )}"
}

output "worker_ep" {
  value = "${aws_instance.worker_node.*.public_dns}"
}

