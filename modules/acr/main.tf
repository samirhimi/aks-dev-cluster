# checkov:skip=CKV_AZURE_139: public network access is gated per-env via var.public_network_access_enabled — dev intentionally allows it, prod disables it.
# checkov:skip=CKV_AZURE_165: geo-replication is out of scope for this single-region stack; revisit if multi-region image promotion is needed.
resource "azurerm_container_registry" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = var.public_network_access_enabled
  zone_redundancy_enabled       = true
  retention_policy_in_days      = 7
  trust_policy_enabled          = true
  quarantine_policy_enabled     = true
  data_endpoint_enabled         = true
  tags                          = var.tags
}
