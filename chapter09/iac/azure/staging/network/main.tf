module "network" {
  source = "../../../modules/network"

  environment                    = "staging"
  location                       = var.location
  address_space                  = ["10.20.0.0/16"]
  workload_subnet_prefix         = "10.20.1.0/24"
  private_endpoint_subnet_prefix = "10.20.2.0/24"
  tags                           = var.tags
}
