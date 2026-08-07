# Input variables for the laravel-cloud-service module.
#
# Every workspace service (identity, commerce, api, ai, ...) is composed
# from this module via a per-service `.tf` file in the env root. The input
# shape mirrors `.kiro/cloud/apps/*.yaml` so an operator can move between
# the two representations mechanically during Phase 4 (state import).

variable "name" {
  description = "Service slug — matches the workspace slug from .kiro/cloud/apps/<slug>.yaml. Used as the Cloud application name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase, start with a letter, and contain only letters, digits, and dashes."
  }
}

variable "organization_id" {
  description = "Cloud organisation ID this service belongs to. ULID shape (org_01H...). See workspace.yaml for canonical IDs per org."
  type        = string
}

variable "region" {
  description = "Deploy region. Immutable post-create. Common values: us-east-1, eu-west-1, ap-southeast-1."
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
  description = "Repository identifier in `owner/repo` shape. Optional — omit for manually-deployed applications."
  type        = string
  default     = null
}

variable "slack_channel" {
  description = "Slack channel for deploy notifications. Optional."
  type        = string
  default     = null
}

variable "cluster_id" {
  description = "Deploy cluster ID. Optional — Cloud picks a default when unset."
  type        = string
  default     = null
}

# ────────────────────────────────────────────────────────────────
# Phase 2 inputs — declared here so the module signature stabilises
# but currently no-op'd until the provider ships the matching resource
# types (environment, database_schema, cache, bucket, websocket_app,
# domain). Consumer HCL can pass these values today; the module ignores
# them cleanly.
# ────────────────────────────────────────────────────────────────

variable "environments" {
  description = "Per-environment configuration. Keys: env slug (dev/stg/prd). Values: env-specific overrides. Consumed in Phase 2 by the laravelcloud_environment resource."
  type = map(object({
    branch    = optional(string)
    variables = optional(map(string), {})
    inherits  = optional(string) # env slug to inherit from
  }))
  default = {}
}

variable "database_cluster_id" {
  description = "Shared database cluster this service's schemas live in. When null the module skips database provisioning. Consumed in Phase 2."
  type        = string
  default     = null
}

variable "websocket_cluster_id" {
  description = "Shared WebSocket cluster this service's ws-apps live in. When null the module skips WS provisioning. Consumed in Phase 2."
  type        = string
  default     = null
}

variable "buckets" {
  description = "S3-compatible buckets this service owns. Each entry maps a logical name → bucket config. Consumed in Phase 2."
  type = list(object({
    name   = string
    region = optional(string)
    mode   = optional(string, "private") # private / public
  }))
  default = []
}

variable "domains" {
  description = "Custom domains bound to this service's environments. Each entry maps env slug → hostname. Consumed in Phase 2."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Free-form tags for cost attribution + audit. Applied to every resource the module creates."
  type        = map(string)
  default     = {}
}
