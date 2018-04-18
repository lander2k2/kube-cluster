variable "master0_ami" {}
variable "master_ami" {}
variable "master_type" {}

resource "aws_security_group" "master_sg" {
  name = "master_sg"

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
    cidr_blocks = ["172.31.0.0/16"]
  }
  ingress {
    from_port   = 10250
    to_port     = 10255
    protocol    = "TCP"
    cidr_blocks = ["172.31.0.0/16"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
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
  count                  = 1
  ami                    = "${var.master0_ami}"
  instance_type          = "${var.master_type}"
  vpc_security_group_ids = ["${aws_security_group.master_sg.id}"]
  key_name               = "${var.key_name}"
  tags {
    Name = "master0"
  }
}

resource "aws_instance" "master_node" {
  count                  = 2
  ami                    = "${var.master_ami}"
  instance_type          = "${var.master_type}"
  vpc_security_group_ids = ["${aws_security_group.master_sg.id}"]
  key_name               = "${var.key_name}"
  tags {
    Name = "master"
  }
}

resource "aws_elb" "api_elb_external" {
  subnets = ["subnet-2c5ee157", "subnet-341e6f5d", "subnet-b7ed22fa"]
  internal = false
  instances = ["${aws_instance.master0_node.id}", "${aws_instance.master_node.*.id}"]
  cross_zone_load_balancing = true

  listener {
    instance_port = 6443
    instance_protocol = "TCP"
    lb_port = 6443
    lb_protocol = "TCP"
  }

  tags {
    Name = "kubernetes API external"
  }
}

resource "aws_elb" "api_elb_internal" {
  subnets = ["subnet-2c5ee157", "subnet-341e6f5d", "subnet-b7ed22fa"]
  internal = true
  instances = ["${aws_instance.master0_node.id}", "${aws_instance.master_node.*.id}"]
  cross_zone_load_balancing = true

  listener {
    instance_port = 6443
    instance_protocol = "TCP"
    lb_port = 6443
    lb_protocol = "TCP"
  }

  tags {
    Name = "kubernetes API internal"
  }
}

output "master0_ep" {
  value = "${aws_instance.master0_node.public_dns}"
}

output "master_ep" {
  value = "${aws_instance.master_node.*.public_dns}"
}

output "api_internal_lb_ep" {
  value = "${aws_elb.api_elb_internal.dns_name}"
}

