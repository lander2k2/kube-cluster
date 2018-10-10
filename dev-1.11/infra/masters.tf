variable "master0_ami" {}
variable "master_type" {}

resource "aws_iam_role" "master_role" {
    name = "${var.cluster_name}_master_role"

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
    name = "${var.cluster_name}_master_policy"
    role = "${aws_iam_role.master_role.id}"

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
        "s3:GetObject",
        "s3:PutObject"
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

resource "aws_iam_instance_profile" "master_profile" {
  name = "${var.cluster_name}_k8s_master_profile"
  role = "${aws_iam_role.master_role.name}"
}

resource "aws_security_group" "master_sg" {
  name   = "master_sg"
  vpc_id = "${aws_vpc.k8s_cluster.id}"

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "TCP"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 10250
    to_port     = 10255
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
    "Name",                                      "${var.cluster_name}-master",
    "KubernetesCluster",                         "${var.cluster_name}",
    "kubernetes.io/cluster/${var.cluster_name}", "owned"
  )}"
}

resource "aws_security_group" "master_lb_sg" {
  name   = "master_lb_sg"
  vpc_id = "${aws_vpc.k8s_cluster.id}"

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "master0_node" {
  count                       = 1
  ami                         = "${var.master0_ami}"
  instance_type               = "${var.master_type}"
  subnet_id                   = "${aws_subnet.k8s_cluster0.id}"
  vpc_security_group_ids      = ["${aws_security_group.master_sg.id}"]
  key_name                    = "${var.key_name}"
  associate_public_ip_address = "true"
  depends_on                  = ["aws_internet_gateway.k8s_cluster"]
  iam_instance_profile        = "${aws_iam_instance_profile.master_profile.name}"
  source_dest_check           = "false"

  tags = "${map(
    "Name",                                      "${var.cluster_name}-master",
    "KubernetesCluster",                         "${var.cluster_name}",
    "kubernetes.io/cluster/${var.cluster_name}", "owned"
  )}"
}

resource "aws_elb" "api_elb_external" {
  subnets                   = ["${aws_subnet.k8s_cluster0.id}"]
  internal                  = "false"
  instances                 = ["${aws_instance.master0_node.id}"]
  security_groups           = ["${aws_security_group.master_lb_sg.id}"]
  cross_zone_load_balancing = "true"

  listener {
    instance_port     = 6443
    instance_protocol = "TCP"
    lb_port           = 6443
    lb_protocol       = "TCP"
  }

  tags = "${map(
    "Name",                                      "${var.cluster_name}-master",
    "KubernetesCluster",                         "${var.cluster_name}",
    "kubernetes.io/cluster/${var.cluster_name}", "owned"
  )}"
}

output "master0_ep" {
  value = "${aws_instance.master0_node.public_dns}"
}

output "master0_ip" {
  value = "${aws_instance.master0_node.private_ip}"
}

output "api_lb_ep" {
  value = "${aws_elb.api_elb_external.dns_name}"
}

