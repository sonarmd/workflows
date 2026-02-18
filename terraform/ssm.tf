# SSM Document: SonarMD-DeployAPI
# Registered in AWS Systems Manager for API deployment via RunCommand

resource "aws_ssm_document" "deploy_api" {
  name            = "SonarMD-DeployAPI"
  document_type   = "Command"
  document_format = "JSON"

  content = file("${path.module}/../ssm-documents/deploy-api.json")

  tags = {
    Name = "SonarMD-DeployAPI"
  }
}
