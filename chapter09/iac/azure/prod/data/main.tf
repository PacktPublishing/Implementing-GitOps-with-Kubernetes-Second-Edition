module "data" {
  source = "../../../modules/data"

  environment = "prod"

  # Supplied by the controller from the network module's outputs Secret.
  resource_group_name        = var.resource_group_name
  location                   = var.location
  vnet_id                    = var.vnet_id
  private_endpoint_subnet_id = var.private_endpoint_subnet_id

  tags = var.tags
}
