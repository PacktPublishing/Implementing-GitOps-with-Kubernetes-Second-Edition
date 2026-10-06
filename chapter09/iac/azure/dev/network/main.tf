module "network" {
  source = "../../../modules/network"

  environment                    = "dev"
  location                       = var.location
  address_space                  = ["10.10.0.0/16"]
  workload_subnet_prefix         = "10.10.1.0/24"
  private_endpoint_subnet_prefix = "10.10.2.0/24"
  tags                           = var.tags
}
