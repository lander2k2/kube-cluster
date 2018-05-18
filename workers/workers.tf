variable "key_name" {}

variable "vpc_id" {}

variable "primary_subnet" {}
variable "secondary_subnet" {}

variable "worker_count" {}
variable "worker_ami" {}
variable "worker_type" {}

provider "aws" {
    version = "1.14.1"
}

resource "aws_security_group" "worker_sg" {
  name   = "worker_sg"
  vpc_id = "${var.vpc_id}"

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
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags {
    Name = "heptio-worker"
    vendor = "heptio"
  }
}

data "local_file" "user_data" {
  filename = "/tmp/kube-workers/worker-bootstrap.sh"
}

resource "aws_launch_configuration" "worker" {
  name_prefix     = "heptio-worker"
  image_id        = "${var.worker_ami}"
  instance_type   = "${var.worker_type}"
  key_name        = "${var.key_name}"
  security_groups = ["${aws_security_group.worker_sg.id}"]
  user_data       = "${data.local_file.user_data.content}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "workers" {
  name                 = "heptio-workers"
  vpc_zone_identifier  = ["${var.primary_subnet}", "${var.secondary_subnet}"]
  desired_capacity     = "${var.worker_count}"
  max_size             = "${var.worker_count + 1}"
  min_size             = "${var.worker_count}"
  launch_configuration = "${aws_launch_configuration.worker.name}"

  tags = [
    {
      key                 = "Name"
      value               = "heptio-workers"
      propagate_at_launch = true
    },
    {
      key                 = "vendor"
      value               = "heptio"
      propagate_at_launch = true
    }
  ]
}

