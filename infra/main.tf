variable "access_key" {}
variable "secret_key" {}
variable "region" {
  default = "us-east-2"
}
variable "key_name" {}

provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

resource "aws_vpc" "k8s_cluster" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = "true"
}

resource "aws_internet_gateway" "k8s_cluster" {
  vpc_id = "${aws_vpc.k8s_cluster.id}"
}

resource "aws_route_table" "k8s_cluster" {
  vpc_id = "${aws_vpc.k8s_cluster.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.k8s_cluster.id}"
  }
}

resource "aws_main_route_table_association" "k8s_cluster" {
  vpc_id         = "${aws_vpc.k8s_cluster.id}"
  route_table_id = "${aws_route_table.k8s_cluster.id}"
}

resource "aws_subnet" "k8s_cluster0" {
  vpc_id     = "${aws_vpc.k8s_cluster.id}"
  cidr_block = "10.0.0.0/18"
}

