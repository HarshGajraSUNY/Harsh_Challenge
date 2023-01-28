variable "region" {
default = "us-west-2"
}
variable "instance_type" {}
variable "instance_key" {}
variable "vpc_cidr" {}
variable "public_subnet_cidr" {}
variable "instance_tenancy" {
  description = "it defines the tenancy of VPC. Whether it's default or dedicated"
  type        = string
  default     = "default"
}
variable "public_dns_name" {
  type        = string
  description = "Public DNS name"
}
variable "iam_user" {
  type = string
}