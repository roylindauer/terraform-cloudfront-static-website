# Cloudfront Static Website


example usage:

```

terraform {
  required_version = ">= 0.14.5"

  backend "s3" {
    bucket = "your-state-bucket"
    key    = "terraform.tfstate"
    region = "us-west-1"

    # Force encryption
    encrypt = true
  }

  required_providers {
    aws = {
      version = "~> 4.12"
    }
  }
}

provider "aws" {
  region = "us-west-1"
}

provider "aws" {
  region = "us-east-1"
  alias  = "use1"
}

module "cloudfront_myapp" {
  source = "./cloudfront-static-website/"
  providers = {
    aws = aws.use1
  }
  domain = {
    zone   = "example.com"
    domain = "app.example.com"
  }
  domain_aliases = [{ "zone" : "example.app", "domain" : example.app" }]
  service        = "app"
  bucket         = "app.prod.example.com"
  acm_arn        = var.ssl_cert_cloudfront.acm_arn

  tags = { "Environment" = "prod", "Description" = "Managed by Terraform", "Creator" = "Terraform", "Name" = "Cloudfront - AMy App", }

}
```
