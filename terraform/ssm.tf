# Register the SSM document for API deployments

resource "aws_ssm_document" "deploy_api" {
  name            = "SonarMD-DeployAPI"
  document_type   = "Command"
  document_format = "JSON"

  content = file("${path.module}/../ssm-documents/deploy-api.json")

  tags = {
    Name = "SonarMD-DeployAPI"
  }
}

output "ssm_document_name" {
  description = "Name of the SSM deploy document"
  value       = aws_ssm_document.deploy_api.name
}
