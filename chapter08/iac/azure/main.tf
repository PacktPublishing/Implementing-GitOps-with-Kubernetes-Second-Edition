# -----------------------------------------------------------------------------
# Resource group and container registry
# -----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_container_registry" "acr" {
  name                = "gitopsch08${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"

  # No admin user, no shared credentials: every consumer authenticates with an
  # Entra identity. This is what removes imagePullSecrets from the cluster.
  admin_enabled = false

  tags = var.tags
}

# -----------------------------------------------------------------------------
# AKS cluster
#
# Three settings distinguish this from the first-edition cluster and are what
# make keyless GitOps possible:
#   oidc_issuer_enabled:       publishes the cluster OIDC discovery document
#   workload_identity_enabled: installs the Entra Workload ID mutating webhook
#   AcrPull on kubelet identity: image pulls without a pull secret
# -----------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Standard"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Entra-integrated authentication with Azure RBAC instead of static kubeconfig
  # certificates. Cluster access is then granted with role assignments, which are
  # themselves auditable Azure resources.
  local_account_disabled = true

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  default_node_pool {
    name                 = "system"
    node_count           = var.node_count
    vm_size              = var.node_vm_size
    os_sku               = "AzureLinux"
    auto_scaling_enabled = true
    min_count            = var.node_count
    max_count            = var.node_count + 2

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    load_balancer_sku   = "standard"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  monitor_metrics {
    # Enables the managed Prometheus metrics agent (see observability/).
  }

  tags = var.tags

  lifecycle {
    # The cluster autoscaler owns node_count once the cluster is running.
    ignore_changes = [default_node_pool[0].node_count]
  }
}

# Let the kubelet pull from ACR using its managed identity. No pull secret, no
# registry password anywhere in Git.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
