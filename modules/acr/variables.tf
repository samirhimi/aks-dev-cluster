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

variable "sku" {
  description = "ACR SKU. Premium is recommended for zone redundancy and private endpoints."
  type        = string
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of Basic, Standard, or Premium."
  }
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
