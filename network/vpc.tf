provider "aws" {
  version = "1.14.1"
	region = "${var.region}"
}

variable "cluster_name" {
  default = "kubernetes"
}

variable "region" {
  default = "us-east-2"
}

variable "primary_az" {
  default = "us-east-2a"
}

variable "secondary_az" {
  default = "us-east-2b"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags {
    Name = "${var.cluster_name}"
  }
}

resource "aws_subnet" "primary_subnet" {
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "10.0.0.0/18"
  availability_zone = "${var.primary_az}"

  tags {
    Name = "${var.cluster_name}-primary"
  }
}

resource "aws_subnet" "secondary_subnet" {
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "10.0.64.0/18"
  availability_zone = "${var.secondary_az}"

  tags {
    Name = "${var.cluster_name}-secondary"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table_association" "public-primary" {
  subnet_id      = "${aws_subnet.primary_subnet.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "public-secondary" {
  subnet_id      = "${aws_subnet.secondary_subnet.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags {
    Name = "${var.cluster_name}-route_table"
  }
}

output "vpc_id" {
  value = "${aws_vpc.vpc.id}"
}

output "primary_subnet" {
  value = "${aws_subnet.primary_subnet.id}"
}

output "secondary_subnet" {
  value = "${aws_subnet.secondary_subnet.id}"
}

