terraform {
  cloud {
    organization = "my-terraform-playground"
    workspaces {
      name = "openvpn-p2p-aliyun"
    }
  }

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "1.214.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "alicloud" {}