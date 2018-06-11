variable "key_name" {}
variable "vpc_id" {}

data "aws_vpc" "existing" {
    id = "${var.vpc_id}"
}

variable "primary_subnet" {}
variable "secondary_subnet" {}

provider "aws" {
    version = "1.14.1"
}

output "vpc_cidr" {
  value = "${data.aws_vpc.existing.cidr_block}"
}

