# Outputs — the surface consuming HCL references.

output "application_id" {
  description = "Cloud-assigned application ID."
  value       = laravelcloud_application.this.id
}

output "application_slug" {
  description = "URL-safe slug derived from name by Cloud. Used to build .laravel.cloud endpoints."
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

# Per-env outputs — maps of env slug → resource ID.

output "environment_ids" {
  description = "Map of env slug → environment ID."
  value       = { for k, v in laravelcloud_environment.envs : k => v.id }
}

output "database_schema_ids" {
  description = "Map of env slug → database schema ID. Empty when database_cluster_id is unset."
  value       = { for k, v in laravelcloud_database_schema.schemas : k => v.id }
}

output "cache_ids" {
  description = "Map of env slug → cache ID. Empty when attach_cache is false."
  value       = { for k, v in laravelcloud_cache.caches : k => v.id }
}

output "websocket_app_ids" {
  description = "Map of env slug → WS app ID. Empty when websocket_cluster_id is unset."
  value       = { for k, v in laravelcloud_websocket_app.ws_apps : k => v.id }
}

output "bucket_ids" {
  description = "Map of <env>-<bucket-name> → bucket ID."
  value       = { for k, v in laravelcloud_bucket.buckets : k => v.id }
}

output "domain_ids" {
  description = "Map of env slug → domain binding ID."
  value       = { for k, v in laravelcloud_domain.domains : k => v.id }
}
