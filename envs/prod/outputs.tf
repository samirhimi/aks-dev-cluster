output "resource_group_name" {
  description = "Resource group hosting the prod AKS cluster."
  value       = module.network.resource_group_name
}

output "aks_name" {
  description = "Name of the prod AKS cluster."
  value       = module.aks.name
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation."
  value       = module.aks.oidc_issuer_url
}

output "acr_login_server" {
  description = "Login server URL for the prod ACR."
  value       = module.acr.login_server
}
