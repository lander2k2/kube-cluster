variable "etcd0_ami" {}
variable "etcd_ami" {}
variable "etcd_type" {
  default = "m4.large"
}
variable "etcd_disk_size" {
  default = 100
}

resource "aws_security_group" "etcd_sg" {
  name   = "etcd_sg"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port       = 2379
    to_port         = 2379
    protocol        = "TCP"
    self            = "true"
    security_groups = ["${aws_security_group.master_sg.id}"]
  }
  ingress {
    from_port = 2380
    to_port   = 2380
    protocol  = "TCP"
    self      = "true"
  }
  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "heptio-etcd"
    vendor = "heptio"
  }
}

resource "aws_instance" "etcd0_node" {
  count                  = 1
  ami                    = "${var.etcd0_ami}"
  instance_type          = "${var.etcd_type}"
  subnet_id              = "${var.primary_subnet}"
  vpc_security_group_ids = ["${aws_security_group.etcd_sg.id}"]
  key_name               = "${var.key_name}"
  ebs_optimized          = "true"

  root_block_device {
    volume_type           = "io1"
    volume_size           = "${var.etcd_disk_size}"
    iops                  = 5000
    delete_on_termination = false
  }

  tags {
    Name   = "heptio-etcd0"
    vendor = "heptio"
  }
}

resource "aws_instance" "etcd_node" {
  count                  = 2
  ami                    = "${var.etcd_ami}"
  instance_type          = "${var.etcd_type}"
  subnet_id              = "${var.primary_subnet}"
  vpc_security_group_ids = ["${aws_security_group.etcd_sg.id}"]
  key_name               = "${var.key_name}"
  ebs_optimized          = "true"

  root_block_device {
    volume_type           = "io1"
    volume_size           = "${var.etcd_disk_size}"
    iops                  = 5000
    delete_on_termination = false
  }

  tags {
    Name   = "heptio-etcd"
    vendor = "heptio"
  }
}

output "etcd0_ep" {
  value = "${aws_instance.etcd0_node.private_dns}"
}
output "etcd0_ip" {
  value = "${aws_instance.etcd0_node.private_ip}"
}

output "etcd_ep" {
  value = "${aws_instance.etcd_node.*.private_dns}"
}
output "etcd_ip" {
  value = "${aws_instance.etcd_node.*.private_ip}"
}

