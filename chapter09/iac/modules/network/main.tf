# -----------------------------------------------------------------------------
# Environment network
#
# One module, three environments. The first edition duplicated this file into
# dev/, staging/ and prod/ and changed only the variable defaults, which meant
# a fix had to be applied three times and could silently be applied twice.
# -----------------------------------------------------------------------------

locals {
  prefix = "gitops-${var.environment}"

  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "tofu-controller"
  })
}

resource "azurerm_resource_group" "main" {
  name     = "${local.prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.prefix}-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = var.address_space
  tags                = local.tags
}

resource "azurerm_subnet" "workload" {
  name                 = "workload"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.workload_subnet_prefix]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoint_subnet_prefix]
}
