# assignments bucket -> SQS -> Lambda (the async step)

resource "aws_s3_bucket" "assignments" {
  bucket        = "${var.prefix}-assignments-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "assignments" {
  bucket                  = aws_s3_bucket.assignments.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# the browser POSTs files straight to S3 from the CloudFront site
resource "aws_s3_bucket_cors_configuration" "assignments" {
  bucket = aws_s3_bucket.assignments.id
  cors_rule {
    allowed_methods = ["POST"]
    allowed_origins = ["https://${aws_cloudfront_distribution.main.domain_name}"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_sqs_queue" "notify_dlq" {
  name = "${var.prefix}-notify-dlq"
}

resource "aws_sqs_queue" "notify" {
  name                       = "${var.prefix}-notify"
  visibility_timeout_seconds = 60
  # after 3 failed tries the message moves to the DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notify_dlq.arn
    maxReceiveCount     = 3
  })
}

# only the assignments bucket may send messages to the queue
resource "aws_sqs_queue_policy" "notify" {
  queue_url = aws_sqs_queue.notify.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.notify.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_s3_bucket.assignments.arn } }
    }]
  })
}

resource "aws_s3_bucket_notification" "assignments" {
  bucket = aws_s3_bucket.assignments.id
  queue {
    queue_arn     = aws_sqs_queue.notify.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "assignments/"
  }
  depends_on = [aws_sqs_queue_policy.notify]
}

# Lambda that reads the queue and logs the tutor notification
data "archive_file" "notify" {
  type        = "zip"
  source_dir  = "${path.module}/../app/lambda"
  output_path = "${path.module}/build/notify.zip"
}

resource "aws_cloudwatch_log_group" "notify" {
  name              = "/aws/lambda/${var.prefix}-notify"
  retention_in_days = 7
}

resource "aws_iam_role" "notify" {
  name = "${var.prefix}-notify-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# read from this one queue and write to this one log group, nothing else
resource "aws_iam_role_policy" "notify" {
  name = "${var.prefix}-notify-access"
  role = aws_iam_role.notify.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.notify.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.notify.arn}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "notify" {
  function_name    = "${var.prefix}-notify"
  role             = aws_iam_role.notify.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.notify.output_path
  source_code_hash = data.archive_file.notify.output_base64sha256
  timeout          = 10
  depends_on       = [aws_cloudwatch_log_group.notify]
}

resource "aws_lambda_event_source_mapping" "notify" {
  event_source_arn = aws_sqs_queue.notify.arn
  function_name    = aws_lambda_function.notify.arn
  batch_size       = 10
}
