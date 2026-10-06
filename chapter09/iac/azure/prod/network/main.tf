module "network" {
  source = "../../../modules/network"

  environment                    = "prod"
  location                       = var.location
  address_space                  = ["10.30.0.0/16"]
  workload_subnet_prefix         = "10.30.1.0/24"
  private_endpoint_subnet_prefix = "10.30.2.0/24"
  tags                           = var.tags
}
