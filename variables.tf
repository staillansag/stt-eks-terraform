# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "bucket_name" {
  description = "The name of the S3 bucket to use."
  type        = string
}

variable "vpc_id" {
  description = "The ID of the existing VPC"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for the private subnets"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for the public subnets"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "The ID of the RDS Security Group to allow traffic to."
  type        = string
}

variable "rds_allowed_port" {
  description = "The port number to allow traffic on."
  type        = number
}