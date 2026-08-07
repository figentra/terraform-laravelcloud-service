# Outputs — the surface consuming HCL references. Every downstream module
# that needs to bind a Cloudflare zone / Doppler config / observability
# probe to this service reaches for these values.

output "application_id" {
  description = "Cloud-assigned application ID (ULID). Immutable."
  value       = laravelcloud_application.this.id
}

output "application_slug" {
  description = "URL-safe slug derived from name by Cloud. Used to build predictable domain names + Doppler project slugs."
  value       = laravelcloud_application.this.slug
}

output "application_name" {
  description = "Human-readable name — matches var.name."
  value       = laravelcloud_application.this.name
}

output "region" {
  description = "Deploy region — matches var.region."
  value       = laravelcloud_application.this.region
}

output "created_at" {
  description = "RFC3339 timestamp of application creation."
  value       = laravelcloud_application.this.created_at
}

# ────────────────────────────────────────────────────────────────
# Phase 2 outputs (placeholders — populated once the matching resources
# land in the provider).
# ────────────────────────────────────────────────────────────────

# output "environment_ids" {
#   description = "Map of env slug → environment ID. Phase 2."
#   value       = { for k, v in laravelcloud_environment.envs : k => v.id }
# }

# output "database_schema_ids" {
#   description = "Map of env slug → database schema ID. Phase 2."
#   value       = { for k, v in laravelcloud_database_schema.schemas : k => v.id }
# }

# output "websocket_app_ids" {
#   description = "Map of env slug → WS app ID. Phase 2."
#   value       = { for k, v in laravelcloud_websocket_app.ws_apps : k => v.id }
# }

# output "bucket_names" {
#   description = "Map of bucket logical name → provisioned Cloud name. Phase 2."
#   value       = { for k, v in laravelcloud_bucket.buckets : k => v.name }
# }
