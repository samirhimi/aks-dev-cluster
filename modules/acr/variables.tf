variable "name" {
  description = "Globally-unique alphanumeric name for the container registry."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to host the ACR."
  type        = string
}

variable "location" {
  description = "Azure region for the ACR."
  type        = string
}

variable "public_network_access_enabled" {
  description = "Whether the registry is reachable from the public internet."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the ACR."
  type        = map(string)
  default     = {}
}
