# laravel-cloud-service module — composes the Laravel Cloud provider
# into a shape a workspace service can consume in one HCL block.
#
# One module invocation per service — see `terraform/envs/dev/main.tf`
# for the composition pattern.
#
# Phase 1 (current): creates the application only.
# Phase 2 (upcoming): adds environments, database schemas, caches,
# WS apps, buckets, domains as the provider ships each resource type.

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
# Phase 2 wiring — placeholder comments so operators reading the
# module signature see the full intended shape without wondering
# whether inputs like `environments` are dead code.
# ────────────────────────────────────────────────────────────────

# Environments — one resource per key in var.environments. Enabled
# in Phase 2 once laravelcloud_environment lands.
#
# resource "laravelcloud_environment" "envs" {
#   for_each      = var.environments
#   application_id = laravelcloud_application.this.id
#   name          = each.key
#   branch        = each.value.branch
#   variables     = each.value.variables
#   inherits_id   = each.value.inherits != null ? laravelcloud_environment.envs[each.value.inherits].id : null
# }

# Database schemas — one per env when var.database_cluster_id is set.
# Enabled in Phase 2 once laravelcloud_database_schema lands.
#
# resource "laravelcloud_database_schema" "schemas" {
#   for_each   = var.database_cluster_id != null ? var.environments : {}
#   cluster_id = var.database_cluster_id
#   name       = "${var.name}_${each.key}"
# }

# WebSocket apps — one per env when var.websocket_cluster_id is set.
# Enabled in Phase 2 once laravelcloud_websocket_app lands.
#
# resource "laravelcloud_websocket_app" "ws_apps" {
#   for_each             = var.websocket_cluster_id != null ? var.environments : {}
#   websocket_cluster_id = var.websocket_cluster_id
#   environment_id       = laravelcloud_environment.envs[each.key].id
# }

# Buckets — one per entry in var.buckets. Enabled in Phase 2.
#
# resource "laravelcloud_bucket" "buckets" {
#   for_each = { for b in var.buckets : b.name => b }
#   name     = "${var.name}-${each.value.name}"
#   region   = coalesce(each.value.region, var.region)
#   mode     = each.value.mode
# }

# Domain bindings — one per (env, hostname) pair. Enabled in Phase 2.
#
# resource "laravelcloud_domain" "domains" {
#   for_each       = var.domains
#   environment_id = laravelcloud_environment.envs[each.key].id
#   hostname       = each.value
# }
