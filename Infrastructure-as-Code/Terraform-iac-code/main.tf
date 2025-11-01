terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# S3 Buckets
resource "aws_s3_bucket" "source_videos" {
  bucket = "${var.project_name}-source-videos-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "processed_videos" {
  bucket = "${var.project_name}-processed-videos-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "web_app" {
  bucket = "${var.project_name}-web-app-${random_id.suffix.hex}"
}

# S3 Bucket Versioning and Encryption
resource "aws_s3_bucket_versioning" "source_videos" {
  bucket = aws_s3_bucket.source_videos.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source_videos" {
  bucket = aws_s3_bucket.source_videos.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_videos" {
  bucket = aws_s3_bucket.processed_videos.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web_app" {
  bucket = aws_s3_bucket.web_app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Policies
resource "aws_s3_bucket_policy" "cloudfront_processed_videos" {
  bucket = aws_s3_bucket.processed_videos.id
  policy = data.aws_iam_policy_document.cloudfront_s3_access.json
}

resource "aws_s3_bucket_policy" "cloudfront_web_app" {
  bucket = aws_s3_bucket.web_app.id
  policy = data.aws_iam_policy_document.cloudfront_s3_access.json
}

# CloudFront Distributions
resource "aws_cloudfront_distribution" "web_app" {
  origin {
    domain_name = aws_s3_bucket.web_app.bucket_regional_domain_name
    origin_id   = "web-app-s3"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "web-app-s3"

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

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_cloudfront_distribution" "video_streaming" {
  origin {
    domain_name = aws_s3_bucket.processed_videos.bucket_regional_domain_name
    origin_id   = "processed-videos-s3"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled         = true
  is_ipv6_enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "processed-videos-s3"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    
    # Enable CORS for video streaming
    response_headers_policy_id = aws_cloudfront_response_headers_policy.cors.id
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# CloudFront OAI
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for media streaming app"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.source_videos.arn}/*",
          "${aws_s3_bucket.processed_videos.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "mediaconvert:CreateJob",
          "mediaconvert:GetJob"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function for Video Processing
resource "aws_lambda_function" "video_processor" {
  filename      = "lambda-function.zip"
  function_name = "${var.project_name}-video-processor"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 300

  environment {
    variables = {
      SOURCE_BUCKET      = aws_s3_bucket.source_videos.bucket
      PROCESSED_BUCKET   = aws_s3_bucket.processed_videos.bucket
      MEDIA_CONVERT_ROLE = aws_iam_role.media_convert_role.arn
    }
  }
}

# S3 Event Trigger for Lambda
resource "aws_lambda_permission" "s3_trigger" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.video_processor.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source_videos.arn
}

resource "aws_s3_bucket_notification" "source_videos_notification" {
  bucket = aws_s3_bucket.source_videos.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.video_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_trigger]
}

# MediaConvert Role
resource "aws_iam_role" "media_convert_role" {
  name = "${var.project_name}-mediaconvert-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "mediaconvert.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "media_convert_policy" {
  name = "${var.project_name}-mediaconvert-policy"
  role = aws_iam_role.media_convert_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.source_videos.arn}/*",
          "${aws_s3_bucket.processed_videos.arn}/*"
        ]
      }
    ]
  })
}

# API Gateway
resource "aws_apigatewayv2_api" "streaming_api" {
  name          = "${var.project_name}-streaming-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.streaming_api.id
  name        = "$default"
  auto_deploy = true
}

# Cognito User Pool
resource "aws_cognito_user_pool" "users" {
  name = "${var.project_name}-user-pool"

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
  }

  username_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "web_client" {
  name         = "${var.project_name}-web-client"
  user_pool_id = aws_cognito_user_pool.users.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

# CloudFront Response Headers Policy for CORS
resource "aws_cloudfront_response_headers_policy" "cors" {
  name = "${var.project_name}-cors-policy"

  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }

    access_control_allow_origins {
      items = ["*"]
    }

    origin_override = true
  }
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Data sources for policies
data "aws_iam_policy_document" "cloudfront_s3_access" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.processed_videos.arn}/*", "${aws_s3_bucket.web_app.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.oai.iam_arn]
    }
  }
}

# Outputs
output "cloudfront_web_url" {
  value = "https://${aws_cloudfront_distribution.web_app.domain_name}"
}

output "cloudfront_video_url" {
  value = "https://${aws_cloudfront_distribution.video_streaming.domain_name}"
}

output "user_pool_id" {
  value = aws_cognito_user_pool.users.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web_client.id
}

output "source_bucket_name" {
  value = aws_s3_bucket.source_videos.bucket
}

output "processed_bucket_name" {
  value = aws_s3_bucket.processed_videos.bucket
}