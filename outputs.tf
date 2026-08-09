/**
 * @file outputs.tf
 * @description Outputs the laravel-cloud-service module publishes.
 *   Env roots bind these into companion resources (Cloudflare DNS
 *   records that CNAME to `<slug>.laravel.cloud`, Doppler secret
 *   writes keyed by env, observability wiring keyed by
 *   `application_id`).
 *
 * Cross-refs:
 *   main.tf                            resources this file exposes
 *   variables.tf                        inputs shaping the outputs
 *   cloudflare-record/variables.tf      sibling — its `content` typically references `application_slug`
 *   doppler-project/outputs.tf          sibling — env-specific secrets keyed by env_slug
 */

output "application_id" {
  description = <<-DESC
    Cloud-assigned application ID (opaque). Used for import paths,
    audit-trail correlation, and any downstream module that needs
    to reference the app without knowing its slug.
  DESC
  value       = laravelcloud_application.this.id
}

output "application_slug" {
  description = <<-DESC
    URL-safe slug derived from `var.name` by Cloud. Used to build
    `<slug>.laravel.cloud` endpoints (Cloud's default hostname
    before custom domains attach). Consumers reference this from
    Cloudflare CNAME record `content` values.
  DESC
  value       = laravelcloud_application.this.slug
}

output "application_name" {
  description = <<-DESC
    Human-readable name — passthrough of `var.name`. Reviewers
    surface this into deploy logs.
  DESC
  value       = laravelcloud_application.this.name
}

output "region" {
  description = <<-DESC
    Deploy region — passthrough of `var.region`. Consumers reference
    it when composing region-specific resources (e.g. an S3 bucket
    in the same region for reduced egress costs).
  DESC
  value       = laravelcloud_application.this.region
}

output "created_at" {
  description = <<-DESC
    RFC3339 timestamp of application creation. Reviewers use this
    for audit trails ("when did this Cloud application first
    provision?").
  DESC
  value       = laravelcloud_application.this.created_at
}

# ────────────────────────────────────────────────────────────────
# Per-env outputs — maps of env slug → resource ID.
# ────────────────────────────────────────────────────────────────

output "environment_ids" {
  description = <<-DESC
    Map of `env slug → environment ID`. Consumers reference an env's
    ID from adjacent resources — e.g. binding a preview-env's
    ScoreCard alerts, or importing an env under a fresh state.
  DESC
  value       = { for k, v in laravelcloud_environment.envs : k => v.id }
}

output "database_schema_ids" {
  description = <<-DESC
    Map of `env slug → database schema ID`. Empty when
    `attach_database=false`. Consumers use these IDs when granting
    per-env DB access to companion IAM roles.
  DESC
  value       = { for k, v in laravelcloud_database_schema.schemas : k => v.id }
}

output "cache_ids" {
  description = <<-DESC
    Map of `env slug → cache ID`. Empty when `attach_cache=false`.
    Consumers use these IDs when configuring cross-env cache
    replication (rare — most services keep caches env-isolated).
  DESC
  value       = { for k, v in laravelcloud_cache.caches : k => v.id }
}

output "websocket_app_ids" {
  description = <<-DESC
    Map of `env slug → WebSocket app ID`. Empty when
    `attach_websocket=false`. Consumers reference these when
    provisioning a status page that reports Reverb health.
  DESC
  value       = { for k, v in laravelcloud_websocket_app.ws_apps : k => v.id }
}

output "bucket_ids" {
  description = <<-DESC
    Map of `<env>-<bucket-name> → bucket ID`. Consumers use these
    IDs to grant cross-env or cross-service bucket policies (rare).
  DESC
  value       = { for k, v in laravelcloud_bucket.buckets : k => v.id }
}

output "domain_ids" {
  description = <<-DESC
    Map of `env slug → domain binding ID`. Consumers use these when
    tracing a specific custom-domain binding through Cloud's audit
    logs.
  DESC
  value       = { for k, v in laravelcloud_domain.domains : k => v.id }
}
