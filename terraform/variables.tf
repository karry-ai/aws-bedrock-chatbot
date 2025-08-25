variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-west-1"
}

variable "profile" {
  description = "AWS Profile"
  type        = string
}

variable "opensearch_mcp_url" {
  description = "Public URL of the OpenSearch MCP server (HTTP/S endpoint)"
  type        = string
}

variable "opensearch_mcp_api_key" {
  description = "API key for the OpenSearch MCP server"
  type        = string
  sensitive   = true
}
