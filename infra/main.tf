variable "key_name" {}
variable "vpc_id" {}

variable "primary_subnet" {}
variable "secondary_subnet" {}

provider "aws" {
    version = "1.14.1"
}

#resource "aws_vpc" "k8s_cluster" {
#  cidr_block           = "10.0.0.0/16"
#  enable_dns_hostnames = "true"
#}

#resource "aws_internet_gateway" "k8s_cluster" {
#  vpc_id = "${aws_vpc.k8s_cluster.id}"
#}

#resource "aws_route_table" "k8s_cluster" {
#  vpc_id = "${aws_vpc.k8s_cluster.id}"
#  route {
#    cidr_block = "0.0.0.0/0"
#    gateway_id = "${aws_internet_gateway.k8s_cluster.id}"
#  }
#}

#resource "aws_main_route_table_association" "k8s_cluster" {
#  vpc_id         = "${aws_vpc.k8s_cluster.id}"
#  route_table_id = "${aws_route_table.k8s_cluster.id}"
#}

#resource "aws_subnet" "k8s_cluster0" {
#  vpc_id     = "${aws_vpc.k8s_cluster.id}"
#  cidr_block = "10.0.0.0/18"
#}

