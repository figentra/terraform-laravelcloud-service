/**
 * @file main.tf
 * @description Composes the Laravel Cloud provider into a shape a
 *   workspace service can consume in one HCL block. Every workspace
 *   service (identity, commerce, api, ai, ...) uses this module once
 *   per env root to declare its Cloud footprint.
 *
 *   Provisions (v0.4.x provider — Cloud API v2 aligned):
 *     - 1× Application (top-level Cloud unit)
 *     - N× environments (dev / stg / prd + preview-*)
 *     - N× database schemas (one per env when `attach_database=true`)
 *     - N× cache instances (one per env when `attach_cache=true`)
 *     - N× WebSocket apps (one per env when `attach_websocket=true`)
 *     - N× buckets (from `var.buckets` × envs)
 *     - N× domain bindings from `var.domains`
 *
 *   Nightwatch env vars (NIGHTWATCH_ENABLED / SAMPLING_RATE /
 *   REDACT_HEADERS / optional LOG_STACK) are computed once per env
 *   in `locals.nightwatch_env_vars` and merged into each env's
 *   `variables` map so caller-supplied entries always win on
 *   collision.
 *
 *   Cloud API v2 changes vs v0.3 (documented for callers migrating):
 *     - `organization_id` is no longer accepted anywhere — it's
 *       derived from the API token's scope. Kept as a no-op variable
 *       for backward compat; drop on the next module major bump.
 *     - `websocket_app` decoupled from environment: it's a
 *       name-scoped Reverb app on the cluster; environments bind via
 *       `websocket_application_id`.
 *     - Bucket: `mode` → `visibility`; `region` → `jurisdiction`;
 *       `key_name` + `key_permission` required.
 *     - Domain: `redirect_from_www` → `www_redirect` (enum);
 *       `verification` → `verification_method`; `cloudflare_managed`
 *       → `cloudflare_strategy` (enum).
 *
 * Cross-refs:
 *   variables.tf                          service knobs + env map + shared cluster IDs
 *   outputs.tf                            application_id / per-env resource IDs
 *   laravel-cloud-static-site/main.tf     sibling module — SPA/static site variant
 *   doppler-project/main.tf               sibling — where runtime secrets live
 */

# ────────────────────────────────────────────────────────────────
# Application — the top-level Cloud unit for this service.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_application" "this" {
  name                         = var.name
  region                       = var.region
  source_control_provider_type = var.source_control_provider_type
  repository                   = var.repository
  root_directory               = var.root_directory
  slack_channel                = var.slack_channel
  cluster_id                   = var.cluster_id
}

# ────────────────────────────────────────────────────────────────
# Database schemas — one per env when var.attach_database=true.
#
# Naming convention: `<service>_<env>` (e.g. `my_service_dev`). This
# matches the workspace's `.kiro/cloud/apps/*.yaml` manifests so the
# import path is 1:1. Dashes in service names are converted to
# underscores because Postgres/MySQL identifiers disallow dashes.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_database_schema" "schemas" {
  for_each = var.attach_database ? var.environments : {}

  cluster_id = var.database_cluster_id
  name       = "${replace(var.name, "-", "_")}_${each.key}"
}

# ────────────────────────────────────────────────────────────────
# Caches — one per env when var.attach_cache is true. Each cache is
# provisioned as a Valkey/Redis instance sized per env-map entry.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_cache" "caches" {
  for_each = var.attach_cache ? var.environments : {}

  name                 = "${var.name}-${each.key}"
  type                 = var.cache_type
  region               = var.region
  size                 = each.value.cache_size
  auto_upgrade_enabled = var.cache_auto_upgrade_enabled
  is_public            = var.cache_is_public
  eviction_policy      = var.cache_eviction_policy
}

# ────────────────────────────────────────────────────────────────
# WebSocket apps — one per env when var.attach_websocket=true.
#
# Cloud API v2 change: ws_apps are now name-scoped resources on the
# cluster (with their own app_key + app_secret), and environments bind
# to them via `websocket_application_id`. One ws_app per env keeps the
# 1:1 semantic parity of pre-v2.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_websocket_app" "ws_apps" {
  for_each = var.attach_websocket ? var.environments : {}

  cluster_id = var.websocket_cluster_id
  name       = "${var.name}-${each.key}"
}

# ────────────────────────────────────────────────────────────────
# Nightwatch env vars — computed per env from var.nightwatch.
#
# On Laravel Cloud, the "Enable Nightwatch" toggle at the app level
# auto-injects NIGHTWATCH_TOKEN + runs the agent as a background
# process. This locals block only sets the OVERRIDES consumers
# typically want per env (enabled flag, sampling rate, redact list,
# optional log stack).
# ────────────────────────────────────────────────────────────────

locals {
  # Default sampling per env — dev cheapest, prd fullest fidelity.
  nightwatch_default_sampling = {
    dev = 0.1
    stg = 0.5
    prd = 1.0
  }

  # Per-env Nightwatch env vars, computed once + merged in below.
  nightwatch_env_vars = {
    for env_key, env_cfg in var.environments : env_key => merge(
      {
        NIGHTWATCH_ENABLED = tostring(
          contains(coalesce(var.nightwatch.enabled_in, ["stg", "prd"]), env_key)
        )
        NIGHTWATCH_SAMPLING_RATE = tostring(
          coalesce(
            try(var.nightwatch.sampling_rate_by_env[env_key], null),
            lookup(local.nightwatch_default_sampling, env_key, 1.0),
          )
        )
        NIGHTWATCH_REDACT_HEADERS = coalesce(
          var.nightwatch.redact_headers,
          "cookie,authorization,x-api-key,x-service-identity,x-doppler-token",
        )
      },
      # LOG_STACK only when caller opted in — never override silently.
      var.nightwatch.log_stack != null ? {
        LOG_STACK = var.nightwatch.log_stack
      } : {},
    )
  }
}

# ────────────────────────────────────────────────────────────────
# Environments — one resource per entry in var.environments.
#
# Note: this resource is declared AFTER the schema/cache/ws_app
# resources so that terraform's dependency graph resolves them first.
# The env's `*_id` bindings reference each of those resources. The
# provider handles the two-step create (POST env → PATCH bindings)
# transparently.
#
# The env's `variables` map is a merge of:
#   1. Nightwatch env-var defaults from var.nightwatch (computed
#      above in locals.nightwatch_env_vars).
#   2. Caller's environments[<env>].variables — WINS on collision so
#      per-env caller overrides always beat the module's defaults.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_environment" "envs" {
  for_each = var.environments

  application_id = laravelcloud_application.this.id
  name           = each.key
  branch         = each.value.branch
  variables      = merge(local.nightwatch_env_vars[each.key], each.value.variables)

  # v0.4.5 — env color per env slug. Default map: dev=green,
  # stg=orange, prd=red. Caller override wins per env.
  color = try(each.value.color, null) != null ? each.value.color : lookup(var.default_env_colors, each.key, null)

  database_schema_id       = var.attach_database ? laravelcloud_database_schema.schemas[each.key].id : null
  cache_id                 = var.attach_cache ? laravelcloud_cache.caches[each.key].id : null
  websocket_application_id = var.attach_websocket ? laravelcloud_websocket_app.ws_apps[each.key].id : null
}

# ────────────────────────────────────────────────────────────────
# Buckets — one per (env, bucket) pair in the crossjoin.
#
# Naming: `<service>-<bucket-name>-<env>` (e.g. `my-service-uploads-prd`).
# Every bucket ships with a root access key named `<name>-root` at
# read_write permission by default; overrideable per bucket via the
# `visibility` / `key_permission` fields in the buckets list.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_bucket" "buckets" {
  for_each = { for pair in flatten([
    for env_key, env in var.environments : [
      for b in var.buckets : {
        key            = "${env_key}-${b.name}"
        env            = env_key
        bucket_name    = b.name
        jurisdiction   = coalesce(b.jurisdiction, var.default_bucket_jurisdiction)
        visibility     = coalesce(b.visibility, "private")
        key_permission = coalesce(b.key_permission, "read_write")
      }
    ]
  ]) : pair.key => pair }

  name           = "${var.name}-${each.value.bucket_name}-${each.value.env}"
  visibility     = each.value.visibility
  jurisdiction   = each.value.jurisdiction
  key_name       = "${var.name}-${each.value.bucket_name}-${each.value.env}-root"
  key_permission = each.value.key_permission
}

# ────────────────────────────────────────────────────────────────
# Domains — one per (env, hostname) pair in var.domains.
#
# var.domains map shape: { <env_slug> = "<hostname>" }. Each pair
# creates a domain binding on the matching env. Cloudflare-managed
# verification by default (matches the workspace's cloudflare
# conventions steering) — override per invocation via var.domain_defaults.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_domain" "domains" {
  for_each = var.domains

  environment_id      = laravelcloud_environment.envs[each.key].id
  name                = each.value
  www_redirect        = var.domain_defaults.www_redirect
  verification_method = var.domain_defaults.verification_method
  cloudflare_strategy = var.domain_defaults.cloudflare_strategy
}
