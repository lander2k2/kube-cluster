variable "worker_ami" {}
variable "worker_type" {}

resource "aws_security_group" "worker_sg" {
  name = "worker_sg"

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "TCP"
    cidr_blocks = ["172.31.0.0/16"]
  }
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "TCP"
    cidr_blocks = ["172.31.0.0/16"]
  }
  ingress {
    from_port   = 30000
    to_port     = 32767
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

resource "aws_instance" "worker_node" {
  count                  = 1
  ami                    = "${var.worker_ami}"
  instance_type          = "${var.worker_type}"
  vpc_security_group_ids = ["${aws_security_group.worker_sg.id}"]
  key_name               = "${var.key_name}"
  tags {
    Name = "worker"
  }
}

output "worker_ep" {
  value = "${aws_instance.worker_node.public_dns}"
}

