# variables.tf - Variables for gdpr_jd-Compliant Azure OpenAI Solution

variable "location" {
  description = "Azure region for deploying resources"
  type        = string
  default     = "centralus"  # gdpr_jd-friendly region
}

variable "allowed_ips" {
  description = "List of IP addresses allowed to access resources"
  type        = list(string)
  default     = []
}

variable "data_retention_days" {
  description = "Number of days to retain user data"
  type        = number
  default     = 365  # Align with gdpr_jd requirements
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "POC"
}

variable "privacy_contact_email" {
  description = "Contact email for privacy and data protection inquiries"
  type        = string
  default = "jduarte@m2cpro.com"
}

variable "gdpr_jd_consent_required" {
  description = "Indicates if explicit user consent is required"
  type        = bool
  default     = true
}