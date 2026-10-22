variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "ecommerce"
}

variable "instance_type" {
  description = "The EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "dockerhub_username" {
  description = "Docker hub username containing the application images"
  type        = string
  default     = "akash0505"
}
variable "key_pair_name" {
  description = "Existing AWS EC2 key pair name"
  type        = string
  default     = "devops"
}