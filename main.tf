# laravel-cloud-service module — composes the Laravel Cloud provider into a
# shape a workspace service can consume in one HCL block.
#
# One module invocation per service. Every workspace service (identity,
# commerce, api, ai, ...) uses this module once per env root to declare its
# Cloud footprint.
#
# What this module creates (v0.2.0 provider — full canonical coverage):
#   - Application (top-level Cloud unit)
#   - N environments (dev / stg / prd + preview-*)
#   - N database schemas (one per env when var.database_cluster_id set)
#   - N cache instances (one per env when var.attach_cache = true)
#   - N WebSocket app bindings (one per env when var.websocket_cluster_id set)
#   - N buckets (from var.buckets)
#   - Domain bindings from var.domains

# ────────────────────────────────────────────────────────────────
# Application — the top-level Cloud unit for this service.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_application" "this" {
  organization_id              = var.organization_id
  name                         = var.name
  region                       = var.region
  source_control_provider_type = var.source_control_provider_type
  repository                   = var.repository
  slack_channel                = var.slack_channel
  cluster_id                   = var.cluster_id
}

# ────────────────────────────────────────────────────────────────
# Environments — one resource per entry in var.environments.
#
# The map key IS the env slug (dev / stg / prd / preview-*). The
# `for_each` binding stays stable across plans so re-ordering the map
# doesn't force replacement.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_environment" "envs" {
  for_each = var.environments

  application_id = laravelcloud_application.this.id
  name           = each.key
  branch         = each.value.branch
  variables      = each.value.variables

  # Optional inheritance from another env (e.g. stg inherits dev). The
  # module accepts an env slug from the same map + resolves it to the
  # inherited env's ID on the fly.
  inherits_id = each.value.inherits != null ? laravelcloud_environment.envs[each.value.inherits].id : null
}

# ────────────────────────────────────────────────────────────────
# Database schemas — one per env when var.database_cluster_id is set.
#
# Naming convention: `<service>_<env>` (e.g. `identity_dev`). This matches
# the workspace's `.kiro/cloud/apps/*.yaml` manifests so the import path
# is 1:1.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_database_schema" "schemas" {
  # for_each keys resolve at plan time via `var.attach_database`
  # (a static bool). The previous shape `var.database_cluster_id
  # != null ? var.environments : {}` derived the key set from a
  # resource-output value (apply-time-unknown), which broke plan.
  # Fix landed 2026-08-04 — Wave 5 plan blocker.
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

  organization_id = var.organization_id
  name            = "${var.name}-${each.key}"
  region          = var.region
  size            = each.value.cache_size
}

# ────────────────────────────────────────────────────────────────
# WebSocket app bindings — one per env when var.websocket_cluster_id
# is set. Binds the env to the shared WS cluster with a per-env max
# connections cap.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_websocket_app" "ws_apps" {
  # See attach_database in variables.tf for the plan-time-known-bool
  # rationale. Same fix (2026-08-04 Wave 5 plan blocker).
  for_each = var.attach_websocket ? var.environments : {}

  cluster_id      = var.websocket_cluster_id
  environment_id  = laravelcloud_environment.envs[each.key].id
  max_connections = each.value.websocket_max_connections
}

# ────────────────────────────────────────────────────────────────
# Buckets — one per entry in var.buckets, per env. Bucket naming:
# `<service>-<bucket>-<env>` (e.g. `identity-uploads-prd`).
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_bucket" "buckets" {
  for_each = { for pair in flatten([
    for env_key, env in var.environments : [
      for b in var.buckets : {
        key    = "${env_key}-${b.name}"
        env    = env_key
        name   = b.name
        region = coalesce(b.region, var.region)
        mode   = coalesce(b.mode, "private")
      }
    ]
  ]) : pair.key => pair }

  organization_id = var.organization_id
  name            = "${var.name}-${each.value.name}-${each.value.env}"
  region          = each.value.region
  mode            = each.value.mode
}

# ────────────────────────────────────────────────────────────────
# Domains — one per (env, hostname) pair in var.domains.
#
# var.domains map shape: { <env_slug> = "<hostname>" }. Each pair
# creates a domain binding on the matching env. Cloudflare-managed
# by default — matches the workspace's cloudflare-conventions steering.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_domain" "domains" {
  for_each = var.domains

  environment_id     = laravelcloud_environment.envs[each.key].id
  name               = each.value
  redirect_from_www  = true
  cloudflare_managed = true
  verification       = "real_time"
}
