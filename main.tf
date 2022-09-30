terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
  }
}

locals {
  s3_origin_id = "myS3Origin"

  all_domains = concat([var.domain.domain], [
    for v in var.domain_aliases : v.domain
  ])

  unique_domains = distinct(local.all_domains)
  
  all_zones = concat([var.domain.zone], [
    for v in var.domain_aliases : v.zone
  ])

  distinct_zones      = distinct(local.all_zones)
  zone_name_to_id_map = zipmap(local.distinct_zones, data.aws_route53_zone.domain[*].zone_id)
  domain_to_zone_map  = zipmap(local.all_domains, local.all_zones)

}

data "aws_route53_zone" "domain" {
  count = length(local.distinct_zones)

  name         = local.distinct_zones[count.index]
  private_zone = false
}

data "aws_cloudfront_cache_policy" "managed_disabled" {
  name = "Managed-CachingDisabled"
}

# Our S3 Bucket. Hosts our static app
resource "aws_s3_bucket" "bucket" {
  bucket = var.bucket
  tags   = var.tags
}

resource "aws_s3_bucket_website_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# ACL Rules for Cloudfront Bucket
resource "aws_s3_bucket_acl" "cluster" {
  bucket = aws_s3_bucket.bucket.bucket
  acl    = "private"
}

# Configure Public Access Block for our Bucket - Block all public access by default
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  block_public_acls   = true
  block_public_policy = true
  restrict_public_buckets = true
  ignore_public_acls = true
}

# IAM - Origin Access Identity (OAI)
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "Cloudfront Origin Access Identity"
}

# Define OAI Access Policy
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.oai.iam_arn]
    }
  }
}

# Attach OAI to S3 Bucket
resource "aws_s3_bucket_policy" "s3_oai" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

# DNS records
resource "aws_route53_record" "dns" {
  count = length(local.unique_domains)

  zone_id = lookup(local.zone_name_to_id_map, lookup(local.domain_to_zone_map, local.unique_domains[count.index]))
  name    = local.unique_domains[count.index]
  type    = "A"

  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.distribution.domain_name
    zone_id                = aws_cloudfront_distribution.distribution.hosted_zone_id
    evaluate_target_health = true
  }
}

# The cloudfront distribution
resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = local.unique_domains

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Index cache
  ordered_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    min_ttl          = 0
    default_ttl      = 0
    max_ttl          = 0
    path_pattern     = "/index.html"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  # Disable Cache for Paths
  dynamic "ordered_cache_behavior" {
    for_each = var.flag_disable_cache_path_pattern ? [1] : []
    content {
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = local.s3_origin_id
      cache_policy_id  = data.aws_cloudfront_cache_policy.managed_disabled.id
      path_pattern     = var.disable_cache_path_pattern
      viewer_protocol_policy = "redirect-to-https"
    }
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = var.tags

  viewer_certificate {
    # cloudfront_default_certificate = true
    acm_certificate_arn = var.acm_arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Angular - Redirect 40x errors to index.html
  custom_error_response {
    error_code = 403
    response_code = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code = 404
    response_code = 200
    response_page_path = "/index.html"
  }
}

