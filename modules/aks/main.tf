# checkov:skip=CKV_AZURE_6: API server authorized IP ranges intentionally not set for this stack; tighten with var.api_server_authorized_ip_ranges before exposing prod.
# checkov:skip=CKV_AZURE_115: private cluster requires VPN/bastion to reach the API server; out of scope for this tutorial stack.
# checkov:skip=CKV_AZURE_117: disk_encryption_set_id requires a Key Vault + DES wired through; not yet provisioned.
# checkov:skip=CKV_AZURE_170: dev intentionally uses sku_tier = "Free" for cost; prod stack passes "Standard".
resource "azurerm_kubernetes_cluster" "this" {
  name                              = "aks-${var.name}"
  location                          = var.location
  resource_group_name               = var.resource_group_name
  dns_prefix                        = "aks-${var.name}"
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = var.sku_tier
  role_based_access_control_enabled = true
  azure_policy_enabled              = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  local_account_disabled            = true
  automatic_upgrade_channel         = var.automatic_upgrade_channel
  node_os_upgrade_channel           = var.node_os_upgrade_channel

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_vm_size
    vnet_subnet_id               = var.subnet_id
    auto_scaling_enabled         = true
    min_count                    = var.system_min_count
    max_count                    = var.system_max_count
    max_pods                     = 50
    host_encryption_enabled      = true
    os_disk_type                 = "Ephemeral"
    os_disk_size_gb              = 64
    only_critical_addons_enabled = true
    orchestrator_version         = var.kubernetes_version
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "cilium"
    load_balancer_sku = "standard"
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                    = "user"
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.this.id
  vm_size                 = var.user_node_vm_size
  vnet_subnet_id          = var.subnet_id
  auto_scaling_enabled    = true
  min_count               = var.user_min_count
  max_count               = var.user_max_count
  max_pods                = 50
  host_encryption_enabled = true
  os_disk_type            = "Ephemeral"
  os_disk_size_gb         = 64
  mode                    = "User"
  orchestrator_version    = var.kubernetes_version
  tags                    = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
