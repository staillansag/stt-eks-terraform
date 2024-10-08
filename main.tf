provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    token                  = data.aws_eks_cluster_auth.cluster.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  }
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

data "aws_vpc" "existing_vpc" {
  id = var.vpc_id
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

locals {
  cluster_name = "eks-${random_string.suffix.result}"
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = data.aws_vpc.existing_vpc.id
  cidr_block              = element(var.private_subnet_cidrs, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = false

  tags = {
    "Name" = "eks-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = 1
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = data.aws_vpc.existing_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    "Name" = "eks-public-${count.index + 1}"
    "kubernetes.io/role/elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
    aws-mountpoint-s3-csi-driver = {
      service_account_role_arn = module.irsa-s3-csi.iam_role_arn
    }
  }

  vpc_id     = data.aws_vpc.existing_vpc.id
  subnet_ids = aws_subnet.public_subnets[*].id

  eks_managed_node_group_defaults = {
    ami_type = var.ami_type
  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = [var.instance_type]

      min_size     = 1
      max_size     = 3
      desired_size = 1
    }

    two = {
      name = "node-group-2"

      instance_types = [var.instance_type]

      min_size     = 1
      max_size     = 3
      desired_size = 1
    }
  }
}

resource "aws_security_group" "lb_sg" {
  name        = "nginx-lb-sg"
  description = "Security group for NGINX Load Balancer"
  vpc_id      = data.aws_vpc.existing_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  namespace  = "ingress-nginx"
  create_namespace = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.7.1"

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-security-groups"
    value = aws_security_group.lb_sg.id
  }

  depends_on = [module.eks]
}

data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_policy" "custom_s3_policy" {
  name        = "CustomS3AccessPolicy-${local.cluster_name}"
  description = "Custom S3 access policy for EKS IRSA"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "MountpointFullBucketAccess",
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::${var.bucket_name}"
        ]
      },
      {
        Sid = "MountpointFullObjectAccess",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject"
        ],
        Resource = [
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      }
    ]
  })
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

module "irsa-s3-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFS3CSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [aws_iam_policy.custom_s3_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:s3-csi-driver-sa"]
}

resource "aws_security_group_rule" "allow_eks_nodes_to_sg" {
  type              = "ingress"
  from_port         = var.rds_allowed_port
  to_port           = var.rds_allowed_port
  protocol          = "tcp"
  security_group_id = var.rds_security_group_id

  source_security_group_id = module.eks.node_security_group_id
}