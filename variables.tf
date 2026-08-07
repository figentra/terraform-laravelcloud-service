# Input variables for the laravel-cloud-service module.
#
# The input shape mirrors `.kiro/cloud/apps/<slug>.yaml` (the legacy
# workspace-tracked manifest) so operators moving from the PHP CLI to
# Terraform have a mechanical 1:1 translation.

variable "name" {
  description = "Service slug — matches the workspace slug from .kiro/cloud/apps/<slug>.yaml. Used as the Cloud application name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase, start with a letter, and contain only letters, digits, and dashes."
  }
}

variable "organization_id" {
  description = "Cloud organisation ID this service belongs to. ULID shape (org_01H...)."
  type        = string
}

variable "region" {
  description = "Deploy region. Immutable post-create."
  type        = string
  default     = "us-east-1"
}

variable "source_control_provider_type" {
  description = "Source control provider — one of github, gitlab, bitbucket. Immutable post-create."
  type        = string
  default     = "github"

  validation {
    condition     = contains(["github", "gitlab", "bitbucket"], var.source_control_provider_type)
    error_message = "source_control_provider_type must be one of: github, gitlab, bitbucket."
  }
}

variable "repository" {
  description = "Repository identifier in `owner/repo` shape."
  type        = string
  default     = null
}

variable "slack_channel" {
  description = "Slack channel for deploy notifications."
  type        = string
  default     = null
}

variable "cluster_id" {
  description = "Deploy cluster ID. Optional — Cloud picks a default when unset."
  type        = string
  default     = null
}

# ────────────────────────────────────────────────────────────────
# Per-environment configuration
# ────────────────────────────────────────────────────────────────

variable "environments" {
  description = "Per-environment configuration. Keys: env slug (dev/stg/prd). Values: env-specific config translated to laravelcloud_environment + cache + websocket resources."
  type = map(object({
    branch                    = optional(string)
    variables                 = optional(map(string), {})
    inherits                  = optional(string) # env slug to inherit from
    cache_size                = optional(string, "valkey-pro.1gb")
    websocket_max_connections = optional(number, 500)
  }))
  default = {}
}

# ────────────────────────────────────────────────────────────────
# Shared cluster bindings
# ────────────────────────────────────────────────────────────────

variable "database_cluster_id" {
  description = "Shared database cluster ID this service's schemas live in. Consumed by the schema resource when attach_database=true."
  type        = string
  default     = null
}

variable "attach_database" {
  description = <<-DESC
    When true, provision one laravelcloud_database_schema per env
    under database_cluster_id. Must be plan-time-known — do NOT
    derive from a resource output (that yields "known after apply"
    which breaks for_each key resolution). Callers set this bool
    statically alongside passing database_cluster_id.
  DESC
  type        = bool
  default     = false
}

variable "attach_cache" {
  description = "When true, provision a per-env Valkey/Redis cache. Size comes from environments[<env>].cache_size."
  type        = bool
  default     = false
}

variable "websocket_cluster_id" {
  description = "Shared WebSocket cluster ID. Consumed by the WS-app resource when attach_websocket=true."
  type        = string
  default     = null
}

variable "attach_websocket" {
  description = <<-DESC
    When true, provision one laravelcloud_websocket_app per env
    binding to websocket_cluster_id. Plan-time-known bool — see
    attach_database for the rationale (for_each keys must resolve
    at plan time; deriving from a resource output blocks the plan).
  DESC
  type        = bool
  default     = false
}

# ────────────────────────────────────────────────────────────────
# Buckets + domains
# ────────────────────────────────────────────────────────────────

variable "buckets" {
  description = "S3-compatible buckets this service owns. Each entry creates one bucket PER ENV. Name pattern: <service>-<bucket>-<env>."
  type = list(object({
    name   = string
    region = optional(string)
    mode   = optional(string, "private") # private / public
  }))
  default = []
}

variable "domains" {
  description = "Custom domains bound to this service's environments. Map shape: { <env> = \"<hostname>\" }."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Free-form tags for cost attribution + audit."
  type        = map(string)
  default     = {}
}
