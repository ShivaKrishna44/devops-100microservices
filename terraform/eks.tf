# =============================================================================
# EKS Cluster + Node Groups
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"

  cluster_name    = "${var.project_name}-cluster"
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint for kubectl access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # IMPORTANT: Disable aws_auth ConfigMap management to avoid cycle
  # The EKS module tries to create a kubernetes resource (ConfigMap) which
  # needs the kubernetes provider, which needs the cluster to exist first = cycle
  manage_aws_auth_configmap = false

  # EKS Managed Node Groups
  # Rolling upgrade: EKS replaces nodes one at a time (max_unavailable = 1)
  # Zero downtime with PDBs + replicas >= 2
  eks_managed_node_groups = {
    main = {
      name           = "${var.project_name}-main-ng"
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Rolling update: only 1 node replaced at a time
      update_config = {
        max_unavailable = 1
      }

      labels = {
        role        = "general"
        environment = var.environment
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"                       = "true"
        "k8s.io/cluster-autoscaler/${var.project_name}-cluster"   = "owned"
      }
    }
  }

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  tags = {
    Environment = var.environment
  }
}

# =============================================================================
# IRSA for EBS CSI Driver
# =============================================================================
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.project_name}-ebs-csi-role"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# =============================================================================
# IRSA for ALB Ingress Controller
# =============================================================================
module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.project_name}-alb-controller-role"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
