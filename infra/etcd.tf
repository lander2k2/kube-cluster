variable "etcd0_ami" {}
variable "etcd_ami" {}
variable "etcd_type" {}

resource "aws_security_group" "etcd_sg" {
  name   = "etcd_sg"
  vpc_id = "${aws_vpc.k8s_cluster.id}"

  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "TCP"
    cidr_blocks = ["10.0.0.0/16"]
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

resource "aws_instance" "etcd0_node" {
  count                       = 1
  ami                         = "${var.etcd0_ami}"
  instance_type               = "${var.etcd_type}"
  subnet_id                   = "${aws_subnet.k8s_cluster0.id}"
  vpc_security_group_ids      = ["${aws_security_group.etcd_sg.id}"]
  key_name                    = "${var.key_name}"
  associate_public_ip_address = "true"
  depends_on                  = ["aws_internet_gateway.k8s_cluster"]
  tags {
    Name = "etcd0"
  }
}

resource "aws_instance" "etcd_node" {
  count                       = 2
  ami                         = "${var.etcd_ami}"
  instance_type               = "${var.etcd_type}"
  subnet_id                   = "${aws_subnet.k8s_cluster0.id}"
  vpc_security_group_ids      = ["${aws_security_group.etcd_sg.id}"]
  key_name                    = "${var.key_name}"
  associate_public_ip_address = "true"
  depends_on                  = ["aws_internet_gateway.k8s_cluster"]
  tags {
    Name = "etcd"
  }
}

output "etcd0_ep" {
  value = "${aws_instance.etcd0_node.public_dns}"
}
output "etcd0_ip" {
  value = "${aws_instance.etcd0_node.private_ip}"
}

output "etcd_ep" {
  value = "${aws_instance.etcd_node.*.public_dns}"
}
output "etcd_ip" {
  value = "${aws_instance.etcd_node.*.private_ip}"
}

