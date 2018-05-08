variable "worker_count" {}
variable "worker_ami" {}
variable "worker_type" {}

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
    from_port   = 10250
    to_port     = 10250
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
  # calico typha
  ingress {
    from_port   = 5473
    to_port     = 5473
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

resource "aws_instance" "worker_node" {
  count                       = "${var.worker_count}"
  ami                         = "${var.worker_ami}"
  instance_type               = "${var.worker_type}"
  subnet_id                   = "${aws_subnet.k8s_cluster0.id}"
  vpc_security_group_ids      = ["${aws_security_group.worker_sg.id}"]
  key_name                    = "${var.key_name}"
  associate_public_ip_address = "true"
  depends_on                  = ["aws_internet_gateway.k8s_cluster"]
  tags {
    Name = "worker"
  }
}

output "worker_ep" {
  value = "${aws_instance.worker_node.*.public_dns}"
}

