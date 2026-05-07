# AKS + ACR Deployment with Terraform

A step-by-step guide to provision an **Azure Kubernetes Service (AKS)** cluster and an **Azure Container Registry (ACR)** using **Terraform**, across two environments: **dev** and **prod**.

This guide follows Azure / Terraform best practices: reusable modules, isolated environments, remote state with locking, and least-privilege identities.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  Azure Subscription                                     │
│                                                         │
│  ┌──────────────────┐         ┌──────────────────┐     │
│  │  rg-aks-dev      │         │  rg-aks-prod     │     │
│  │                  │         │                  │     │
│  │  ┌────────────┐  │         │  ┌────────────┐  │     │
│  │  │  VNet/Subnet│ │         │  │  VNet/Subnet│ │     │
│  │  └─────┬──────┘  │         │  └─────┬──────┘  │     │
│  │        │         │         │        │         │     │
│  │  ┌─────▼──────┐  │         │  ┌─────▼──────┐  │     │
│  │  │   AKS-dev  │  │  AcrPull│  │  AKS-prod  │  │     │
│  │  └─────┬──────┘  │  ◄──────┤  └─────┬──────┘  │     │
│  │        │         │         │        │         │     │
│  └────────┼─────────┘         └────────┼─────────┘     │
│           │                            │               │
│           └────────────┬───────────────┘               │
│                        ▼                               │
│           ┌─────────────────────────┐                  │
│           │  ACR (Premium, shared)  │                  │
│           └─────────────────────────┘                  │
│                                                        │
│  ┌──────────────────────────────────────────────┐     │
│  │  rg-tfstate (remote state + state locking)   │     │
│  │   - Storage Account                          │     │
│  │   - Container: tfstate                       │     │
│  └──────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────┘
```

**Design decisions:**
- One **shared ACR** (Premium SKU) consumed by both clusters → cheaper, simpler image promotion dev → prod.
- Each environment has its **own resource group, VNet, and AKS cluster** → strong blast-radius isolation.
- **Remote state** in Azure Storage with one state file per environment.
- **Modules** keep environment configs DRY.

---

## 2. Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| Terraform | ≥ 1.6 | `terraform version` |
| Azure CLI | ≥ 2.50 | `az version` |
| kubectl | latest | `kubectl version --client` |
| An Azure subscription with **Owner** or **Contributor + User Access Administrator** rights | — | `az account show` |

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

---

## 3. Recommended Repository Layout

```
aks-dev-cluster/
├── README.md
├── .gitignore
├── bootstrap/                  # one-time: creates the remote-state backend
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── modules/                    # reusable building blocks
│   ├── network/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── acr/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── aks/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── envs/
    ├── dev/
    │   ├── backend.tf
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars
    └── prod/
        ├── backend.tf
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars
```

> **Why this layout?** Each environment is its own Terraform root module with its own state file. Shared logic lives in `modules/`. This is the pattern recommended by HashiCorp for multi-env Azure projects.

---

## 4. Step-by-Step Guide

### Step 1 — Initialize the repo

```bash
cd /home/devops/aks-dev-cluster
git init
```

Create a `.gitignore`:

```gitignore
# Local .terraform directories
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfvars.local
crash.log
override.tf
override.tf.json
*_override.tf
.terraform.lock.hcl.bak
```

> ⚠️ **Never commit** `*.tfstate` or secret-bearing `*.tfvars` files. Use `terraform.tfvars` for non-secret values only.

---

### Step 2 — Bootstrap the remote backend (one-time)

The backend stores state remotely so multiple operators / CI can collaborate safely (with locking).

In `bootstrap/main.tf`:

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-tfstate"
  location = "westeurope"
}

resource "azurerm_storage_account" "tfstate" {
  name                          = "sttfstate${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.tfstate.name
  location                      = azurerm_resource_group.tfstate.location
  account_tier                  = "Standard"
  account_replication_type      = "GRS"
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = true
  blob_properties { versioning_enabled = true }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

output "storage_account_name" { value = azurerm_storage_account.tfstate.name }
```

Run it:

```bash
cd bootstrap
terraform init
terraform apply
# Note the storage_account_name output — you'll need it in step 3.
cd ..
```

> 💡 The bootstrap state is kept locally (it's tiny and only changes if you rotate the backend). Commit only the `.tf` files, not its state.

---

### Step 3 — Configure the backend per environment

Each env points to **the same** storage account but a **different state key**.

`envs/dev/backend.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstateXXXXXX"   # output from step 2
    container_name       = "tfstate"
    key                  = "aks/dev.tfstate"
    use_azuread_auth     = true
  }
}
```

`envs/prod/backend.tf` is identical except `key = "aks/prod.tfstate"`.

---

### Step 4 — Build the modules

#### `modules/network/main.tf`

```hcl
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_cidr]
}
```

#### `modules/acr/main.tf`

```hcl
resource "azurerm_container_registry" "this" {
  name                          = var.name                 # globally unique, alphanum
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku                  # "Premium" recommended
  admin_enabled                 = false                    # use AAD/MI, not admin user
  public_network_access_enabled = var.public_network_access_enabled
  zone_redundancy_enabled       = var.sku == "Premium"
  tags                          = var.tags
}
```

#### `modules/aks/main.tf` (key parts)

```hcl
resource "azurerm_kubernetes_cluster" "this" {
  name                              = "aks-${var.name}"
  location                          = var.location
  resource_group_name               = var.resource_group_name
  dns_prefix                        = "aks-${var.name}"
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = var.sku_tier         # "Standard" or "Free"
  role_based_access_control_enabled = true
  azure_policy_enabled              = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  local_account_disabled            = true                 # AAD-only access

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  default_node_pool {
    name                 = "system"
    vm_size              = var.system_node_vm_size
    vnet_subnet_id       = var.subnet_id
    auto_scaling_enabled = true
    min_count            = var.system_min_count
    max_count            = var.system_max_count
    only_critical_addons_enabled = true
    orchestrator_version = var.kubernetes_version
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "cilium"
    load_balancer_sku = "standard"
  }

  identity { type = "SystemAssigned" }

  tags = var.tags
}

# User node pool (workloads)
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  vnet_subnet_id        = var.subnet_id
  auto_scaling_enabled  = true
  min_count             = var.user_min_count
  max_count             = var.user_max_count
  mode                  = "User"
}

# Allow this AKS cluster's kubelet identity to pull from ACR
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
```

> **Why these defaults?**
> - `local_account_disabled = true` + AAD RBAC → no static admin kubeconfig.
> - `oidc_issuer_enabled` + `workload_identity_enabled` → modern, password-less pod-to-Azure auth.
> - `sku_tier = "Standard"` for prod → SLA-backed control plane (use `Free` for dev to save cost).
> - Separate `system` and `user` node pools → system pods can't be evicted by workloads.
> - `AcrPull` is granted via role assignment → no image-pull secrets needed.

---

### Step 5 — Wire up the dev environment

`envs/dev/main.tf`:

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

provider "azurerm" { features {} }

locals {
  env  = "dev"
  tags = { environment = local.env, managedBy = "terraform" }
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
  name                          = var.acr_name              # e.g. "acrshared01abc"
  resource_group_name           = module.network.resource_group_name
  location                      = var.location
  sku                           = "Premium"
  public_network_access_enabled = true
  tags                          = local.tags
}

module "aks" {
  source                  = "../../modules/aks"
  name                    = local.env
  resource_group_name     = module.network.resource_group_name
  location                = var.location
  kubernetes_version      = var.kubernetes_version
  sku_tier                = "Free"
  subnet_id               = module.network.aks_subnet_id
  acr_id                  = module.acr.id
  admin_group_object_ids  = var.admin_group_object_ids
  system_node_vm_size     = "Standard_D2s_v5"
  system_min_count        = 1
  system_max_count        = 2
  user_node_vm_size       = "Standard_D2s_v5"
  user_min_count          = 1
  user_max_count          = 3
  tags                    = local.tags
}
```

`envs/dev/terraform.tfvars`:

```hcl
location               = "westeurope"
kubernetes_version     = "1.30"
acr_name               = "acrsharedmyorgdev01"
admin_group_object_ids = ["<AAD-group-objectId-of-cluster-admins>"]
```

---

### Step 6 — Wire up the prod environment

`envs/prod/main.tf` mirrors dev with **bigger nodes, higher counts, paid tier**:

```hcl
module "aks" {
  source              = "../../modules/aks"
  name                = "prod"
  ...
  sku_tier            = "Standard"
  system_node_vm_size = "Standard_D4s_v5"
  system_min_count    = 2
  system_max_count    = 4
  user_node_vm_size   = "Standard_D4s_v5"
  user_min_count      = 3
  user_max_count      = 10
}
```

Use a **different VNet CIDR** (e.g. `10.20.0.0/16`) so dev and prod can later be peered.

---

### Step 7 — Deploy dev

```bash
cd envs/dev
terraform init
terraform validate
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

Then connect:

```bash
az aks get-credentials \
  --resource-group rg-aks-dev \
  --name aks-dev

kubectl get nodes
```

---

### Step 8 — Deploy prod

```bash
cd ../prod
terraform init
terraform plan -out=prod.tfplan
terraform apply prod.tfplan
```

> 🔒 **Best practice:** require **manual approval** before `apply` in prod. In CI, gate this on a PR review or environment protection rule.

---

### Step 9 — Push an image to ACR and deploy it

```bash
ACR=$(terraform -chdir=envs/dev output -raw acr_login_server)

az acr login --name "${ACR%%.*}"
docker tag myapp:latest  $ACR/myapp:1.0.0
docker push              $ACR/myapp:1.0.0

kubectl create deployment myapp --image=$ACR/myapp:1.0.0
kubectl expose deployment myapp --port=80 --type=LoadBalancer
```

The `AcrPull` role assignment from Step 4 means **no `imagePullSecrets` are needed**.

---

## 5. Best Practices Checklist

| Area | Recommendation |
|---|---|
| **State** | Remote backend (Azure Storage), one state per env, blob versioning ON, state locking via blob lease |
| **Identity** | AAD-integrated AKS, `local_account_disabled = true`, workload identity for pods |
| **Secrets** | Never in `tfvars` committed to git — use Key Vault + `azurerm_key_vault_secret` data sources, or `TF_VAR_*` env vars in CI |
| **Networking** | Azure CNI, separate VNet per env, distinct CIDR ranges, NSGs at subnet level |
| **Node pools** | Separate `system` (tainted) and `user` pools, autoscaler enabled, ephemeral OS disks where possible |
| **ACR** | `Premium` SKU, `admin_enabled = false`, role-based pull from AKS, image scanning enabled (Defender for Containers) |
| **Versioning** | Pin `azurerm` provider (`~> 4.0`), pin `kubernetes_version`, commit `.terraform.lock.hcl` |
| **CI/CD** | `fmt → validate → plan → manual approval → apply`; OIDC federation from GitHub/GitLab to Azure (no static SP secret) |
| **Cost** | Dev: `sku_tier = "Free"`, small VMs, `min_count = 1`, scale-down enabled. Prod: `Standard` tier, multi-AZ |
| **Observability** | Enable AKS diagnostic settings → Log Analytics; enable Container Insights addon |
| **Upgrades** | Subscribe to a release channel (`automatic_channel_upgrade = "patch"` for dev, `"none"` for prod with planned upgrades) |

---

## 6. Day-2 Operations

```bash
# View what would change
terraform -chdir=envs/dev plan

# Format & validate everything
terraform fmt -recursive
terraform -chdir=envs/dev validate

# Tear down a non-prod environment
terraform -chdir=envs/dev destroy
```

---

## 7. Next Steps

1. Add a **GitHub Actions** workflow (`plan` on PR, `apply` on merge to `main`) using OIDC federation.
2. Add **Azure Key Vault** + CSI driver for secret injection into pods.
3. Add **Application Gateway Ingress Controller** or **NGINX ingress** + cert-manager.
4. Add **monitoring** (Container Insights, Prometheus/Grafana managed addons).
5. Add **policy** (Azure Policy for AKS, OPA/Gatekeeper) before the first prod workload.
