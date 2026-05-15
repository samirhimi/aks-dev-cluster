output "id" {
  description = "Resource ID of the container registry."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Name of the container registry."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Fully qualified login server URL of the ACR (e.g. myacr.azurecr.io)."
  value       = azurerm_container_registry.this.login_server
}
