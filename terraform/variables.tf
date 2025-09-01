variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-2"
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

variable "vpc_endpoint_num_subnets" {
  description = "Number of subnets to attach to each Interface VPC Endpoint (use 1 to reduce cost)"
  type        = number
  default     = 1
}
