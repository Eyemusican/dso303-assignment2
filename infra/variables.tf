variable "region" {
  default = "ap-south-1"
}

variable "prefix" {
  default = "tenzin-a2"
}

variable "azs" {
  default = ["ap-south-1a", "ap-south-1b"]
}

# set by the pipeline to the git SHA
variable "image_tag" {
  default = "latest"
}
