terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  env = "dev"
  tags = {
    environment = local.env
    managedBy   = "terraform"
  }
}

module "network" {
  source              = "../../modules/network"
  name                = local.env
  resource_group_name = "rg-aks-${local.env}"
  location            = var.location
  vnet_cidr           = "10.10.0.0/16"
  aks_subnet_cidr     = "10.10.1.0/24"
  tags                = local.tags
}

module "acr" {
  source                        = "../../modules/acr"
  name                          = var.acr_name
  resource_group_name           = module.network.resource_group_name
  location                      = var.location
  sku                           = "Premium"
  public_network_access_enabled = true
  tags                          = local.tags
}

module "aks" {
  source                 = "../../modules/aks"
  name                   = local.env
  resource_group_name    = module.network.resource_group_name
  location               = var.location
  kubernetes_version     = var.kubernetes_version
  sku_tier               = "Free"
  subnet_id              = module.network.aks_subnet_id
  acr_id                 = module.acr.id
  admin_group_object_ids = var.admin_group_object_ids
  system_node_vm_size    = "Standard_D2s_v5"
  system_min_count       = 1
  system_max_count       = 2
  user_node_vm_size      = "Standard_D2s_v5"
  user_min_count         = 1
  user_max_count         = 3
  tags                   = local.tags
}
