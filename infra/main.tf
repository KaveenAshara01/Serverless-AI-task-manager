################################
# DynamoDB
################################
resource "aws_dynamodb_table" "tasks" {
  name           = var.table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
  tags = {
    Project = "serverless-ai-task-manager"
  }
}

################################
# IAM Role for Lambdas (least-privilege)
################################
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "saim-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "saim-lambda-policy"
  description = "Allow DynamoDB PutItem/Scan and CloudWatch logs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.tasks.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

################################
# Package Lambdas (zips)
# Assumes your lambda code is in ../lambdas/<name>
################################
data "archive_file" "create_task_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/createTask"
  output_path = "${path.module}/createTask.zip"
}

data "archive_file" "get_tasks_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/getTasks"
  output_path = "${path.module}/getTasks.zip"
}

################################
# Lambda Functions
################################
resource "aws_lambda_function" "create_task" {
  filename         = data.archive_file.create_task_zip.output_path
  function_name    = "saim-createTask"
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = data.archive_file.create_task_zip.output_base64sha256
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.tasks.name
      HF_API_KEY = var.hf_api_key
    }
  }
  timeout = 10
  memory_size = 256
}

resource "aws_lambda_function" "get_tasks" {
  filename         = data.archive_file.get_tasks_zip.output_path
  function_name    = "saim-getTasks"
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = data.archive_file.get_tasks_zip.output_base64sha256
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.tasks.name
    }
  }
  timeout = 10
  memory_size = 128
}

################################
# API Gateway (REST) - /tasks
################################
resource "aws_api_gateway_rest_api" "api" {
  name        = "saim-api"
  description = "Serverless AI Task Manager API"
}

# Root resource id: aws_api_gateway_rest_api.api.root_resource_id

resource "aws_api_gateway_resource" "tasks" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "tasks"
}

# POST /tasks -> create_task lambda
resource "aws_api_gateway_method" "post_tasks" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.tasks.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "post_tasks_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.tasks.id
  http_method = aws_api_gateway_method.post_tasks.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.create_task.invoke_arn
}

# GET /tasks -> get_tasks lambda
resource "aws_api_gateway_method" "get_tasks" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.tasks.id
  http_method   = "GET"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "get_tasks_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.tasks.id
  http_method = aws_api_gateway_method.get_tasks.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.get_tasks.invoke_arn
}

# Allow API Gateway to invoke Lambdas
resource "aws_lambda_permission" "apigw_invokes_create" {
  statement_id  = "AllowAPIGatewayInvokeCreate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_task.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invokes_get" {
  statement_id  = "AllowAPIGatewayInvokeGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_tasks.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# Deployment & Stage
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Force new deployment whenever integration or method changes
  triggers = {
    create_task_sha = aws_lambda_function.create_task.source_code_hash
    get_tasks_sha   = aws_lambda_function.get_tasks.source_code_hash
  }
  depends_on = [
    aws_api_gateway_integration.post_tasks_integration,
    aws_api_gateway_integration.get_tasks_integration
  ]
}

resource "aws_api_gateway_stage" "stage" {
  rest_api_id    = aws_api_gateway_rest_api.api.id
  deployment_id  = aws_api_gateway_deployment.deployment.id
  stage_name     = "prod"
  xray_tracing_enabled = false
}

################################
# API Key + Usage Plan
################################
resource "aws_api_gateway_api_key" "saim_api_key" {
  name        = "saim-api-key"
  description = "API key for Serverless AI Task Manager"
  enabled     = true
}

resource "aws_api_gateway_usage_plan" "saim_usage" {
  name = "saim-usage-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.stage.stage_name
  }
  throttle_settings {
    burst_limit = 50
    rate_limit  = 20
  }
}

resource "aws_api_gateway_usage_plan_key" "usage_key" {
  key_id        = aws_api_gateway_api_key.saim_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.saim_usage.id
}

################################
# IAM role and policy attachments handled earlier
################################
