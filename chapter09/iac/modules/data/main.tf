# -----------------------------------------------------------------------------
# Environment data plane
#
# Depends on the network module, but not through a terraform_remote_state data
# source. The dependency is expressed at the controller level with
# .spec.dependsOn, which lets each module reconcile on its own interval and
# fail independently.
# -----------------------------------------------------------------------------

locals {
  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "tofu-controller"
  })
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "main" {
  name                     = "gitops${var.environment}${random_string.suffix.result}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "prod" ? "ZRS" : "LRS"

  # Checkov CKV_AZURE_59, CKV_AZURE_44, CKV_AZURE_190: no anonymous access,
  # TLS 1.2 minimum, no shared key authorization.
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access_enabled   = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.environment == "prod" ? 30 : 7
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Private DNS
#
# A private endpoint alone is not enough. public_network_access_enabled is
# false, so the account's public FQDN resolves to an address that refuses the
# connection. The privatelink zone rewrites that FQDN to the endpoint's private
# address for anything inside the virtual network, which is what lets the
# application use the blob_endpoint output unchanged.
#
# Without this, the application deploys, reports healthy, and cannot reach its
# storage: a failure the cluster has no way to see.
# -----------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

# azurerm 5.0 removed private_dns_zone_name and resource_group_name here in
# favour of private_dns_zone_id.
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                 = "gitops-${var.environment}-blob-link"
  private_dns_zone_id  = azurerm_private_dns_zone.blob.id
  virtual_network_id   = var.vnet_id
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "gitops-${var.environment}-blob-pe"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  # Registers the endpoint's private address in the zone above, so the
  # blob_endpoint output resolves correctly from inside the network.
  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = local.tags
}
