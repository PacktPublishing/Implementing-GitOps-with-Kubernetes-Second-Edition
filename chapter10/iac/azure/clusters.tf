# -----------------------------------------------------------------------------
# Three AKS clusters from one definition
#
#   mgmt     Argo CD hub and Kargo. Runs no application workloads.
#   nonprod  dev and staging, one namespace each.
#   prod     production only.
#
# Every cluster has the same keyless baseline as Chapter 8 (OIDC issuer, Entra
# Workload ID, Entra authentication with Azure RBAC, no local accounts) plus two
# Chapter 10 additions: the cluster autoscaler on the system pool, and the
# managed Vertical Pod Autoscaler, used in recommendation mode only (H4).
# -----------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  for_each = var.clusters

  name                = "aks-ch10-${each.key}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aks-ch10-${each.key}"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = each.key == "prod" ? "Standard" : "Free"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  local_account_disabled    = true

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  default_node_pool {
    name                 = "system"
    vm_size              = each.value.node_vm_size
    os_sku               = "AzureLinux"
    auto_scaling_enabled = true
    min_count            = each.value.min_nodes
    max_count            = each.value.max_nodes
    zones                = ["1", "2", "3"]

    upgrade_settings {
      max_surge = "33%"
    }
  }

  # Node-level scaling: the cluster autoscaler adds nodes when pods are
  # Pending. AKS node auto-provisioning (Karpenter-based) is the alternative
  # discussed in the chapter.
  auto_scaler_profile {
    balance_similar_node_groups = true
    scale_down_unneeded         = "5m"
  }

  # Recommendation-only VPA. KEDA is NOT enabled here: it is installed through
  # GitOps on every workload cluster so that AKS and EKS run the same version.
  workload_autoscaler_profile {
    vertical_pod_autoscaler_enabled = true
  }

  # Planned maintenance: Kubernetes patch upgrades only in a weekly window.
  automatic_upgrade_channel = "patch"
  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
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

  tags = merge(var.tags, { role = each.value.role })

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  for_each = azurerm_kubernetes_cluster.this

  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = each.value.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# The person running the walkthrough administers every cluster through Entra
# ID. In a team setting, assign this role to an Entra group instead (Chapter 12).
resource "azurerm_role_assignment" "operator_cluster_admin" {
  for_each = azurerm_kubernetes_cluster.this

  scope                = each.value.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
