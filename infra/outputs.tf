output "api_invoke_url" {
  description = "Base URL for invoking the API (use stage 'prod')"
  value       = "${aws_api_gateway_deployment.deployment.invoke_url}/prod"
}

output "api_gateway_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/tasks"
}

output "api_key_value" {
  description = "API key value (sensitive) - keep private"
  value       = aws_api_gateway_api_key.saim_api_key.value
  sensitive   = true
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tasks.name
}

output "create_task_lambda_arn" {
  value = aws_lambda_function.create_task.arn
}

output "get_tasks_lambda_arn" {
  value = aws_lambda_function.get_tasks.arn
}
output "cognito_user_pool_domain" {
  description = "Cognito User Pool domain URL for JWT token requests"
  value       = "https://${aws_cognito_user_pool_domain.user_pool_domain.domain}.auth.${var.aws_region}.amazoncognito.com"
}
