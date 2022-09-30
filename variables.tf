variable "service" {
  type = string
}

variable "bucket" {
  type = string
}

variable "domain" {
  type = map(string)
}

variable "domain_aliases" {
  type = list(map(string))
}

variable "tags" {
  type = map(string)
}

variable "acm_arn" {
  type = string
}

variable "redirect" {
  type = string
  default = ""
}

variable "flag_disable_cache_path_pattern" {
  type = bool
  default = false
}

variable "disable_cache_path_pattern" {
  type = string
  default = ""
}
