variable "name" {
  type = string
}

variable "docker_compose" {
    type        = string
}

variable "project" {
    type        = string
}

variable "environment" {
    type        = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "subnet_id" {
  type = string
}

variable "public_ssh_keys" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "availability_zone" {
  type = string
}