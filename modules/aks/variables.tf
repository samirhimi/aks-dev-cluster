variable "name" {
  description = "Short environment name used to compose AKS resource names (e.g. dev, prod)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that hosts the AKS cluster."
  type        = string
}

variable "location" {
  description = "Azure region for the cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy (e.g. 1.30)."
  type        = string
}

variable "sku_tier" {
  description = "AKS control-plane SKU. Use Standard for prod, Free for dev."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be one of Free, Standard, or Premium."
  }
}

variable "subnet_id" {
  description = "Subnet ID for AKS node pools."
  type        = string
}

variable "acr_id" {
  description = "Resource ID of the ACR that the cluster kubelet identity will be granted AcrPull on."
  type        = string
}

variable "admin_group_object_ids" {
  description = "AAD group object IDs that get cluster-admin via Azure RBAC."
  type        = list(string)
  default     = []
}

variable "system_node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "system_min_count" {
  description = "Minimum node count for the autoscaled system pool."
  type        = number
  default     = 1
}

variable "system_max_count" {
  description = "Maximum node count for the autoscaled system pool."
  type        = number
  default     = 2
}

variable "user_node_vm_size" {
  description = "VM size for the user (workload) node pool."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "user_min_count" {
  description = "Minimum node count for the autoscaled user pool."
  type        = number
  default     = 1
}

variable "user_max_count" {
  description = "Maximum node count for the autoscaled user pool."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags applied to all AKS resources."
  type        = map(string)
  default     = {}
}
