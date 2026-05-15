terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate8bc0fe"
    container_name       = "tfstate"
    key                  = "aks/prod.tfstate"
    use_azuread_auth     = true
  }
}
