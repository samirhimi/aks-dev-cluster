variable "location" {
  description = "Azure region for all prod resources."
  type        = string
  default     = "westeurope"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster."
  type        = string
  default     = "1.30"
}

variable "acr_name" {
  description = "Globally-unique alphanumeric name for the prod ACR."
  type        = string
}

variable "admin_group_object_ids" {
  description = "AAD group object IDs granted cluster-admin via Azure RBAC."
  type        = list(string)
  default     = []
}
