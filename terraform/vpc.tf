# =============================================================================
# VPC + Networking
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 3)]

  enable_nat_gateway   = true
  single_nat_gateway   = false  # HA: one NAT per AZ in prod
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for EKS and ALB controller
  public_subnet_tags = {
    "kubernetes.io/role/elb"                              = 1
    "kubernetes.io/cluster/${var.project_name}-cluster"   = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                     = 1
    "kubernetes.io/cluster/${var.project_name}-cluster"   = "shared"
  }

  tags = {
    Environment = var.environment
  }
}
