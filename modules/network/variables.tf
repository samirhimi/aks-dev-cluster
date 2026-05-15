variable "name" {
  description = "Short environment name used to compose resource names (e.g. dev, prod)."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that hosts the network resources."
  type        = string
}

variable "location" {
  description = "Azure region for the resource group and VNet."
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR block for the virtual network."
  type        = string
}

variable "aks_subnet_cidr" {
  description = "CIDR block for the AKS node subnet (must be within vnet_cidr)."
  type        = string
}

variable "tags" {
  description = "Tags applied to all network resources."
  type        = map(string)
  default     = {}
}
