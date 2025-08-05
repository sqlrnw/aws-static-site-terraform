provider "aws" {
  region = "us-east-1"
}

# 🪣 إنشاء S3 Bucket
resource "aws_s3_bucket" "static_site" {
  bucket = "mohamedragap-static-site-001" # غيّره لو مش فريد
  force_destroy = true

  tags = {
    Name        = "StaticSiteBucket"
    Environment = "Dev"
  }
}

# 🚫 تعطيل الحماية اللي بتمنع الـ public access
resource "aws_s3_bucket_public_access_block" "static_site" {
  bucket = aws_s3_bucket.static_site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 🌍 تفعيل Static Website Hosting
resource "aws_s3_bucket_policy" "allow_cloudfront_only" {
  bucket = aws_s3_bucket.static_site.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.static_site]
}

resource "null_resource" "upload_site_files" {
  provisioner "local-exec" {
    command = "aws s3 cp ./index.html s3://${aws_s3_bucket.static_site.bucket}/index.html  && aws s3 cp ./error.html s3://${aws_s3_bucket.static_site.bucket}/error.html "
  }

  depends_on = [
    aws_s3_bucket_policy.allow_cloudfront_only
  ]
}

resource "aws_cloudfront_origin_access_control" "s3_access" {
  name                              = "s3-access-control"
  description                       = "Access control for S3 from CloudFront"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "s3-origin"

    origin_access_control_id = aws_cloudfront_origin_access_control.s3_access.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-origin"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true  # HTTPS تلقائي بدون دومين مخصص
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "StaticSiteCDN"
  }

}

