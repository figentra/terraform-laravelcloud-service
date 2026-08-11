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
  #
  # KNOWN LIMITATION (documented in provider v0.6.0 schema): Cloud
  # accepts `color` on PATCH but silently drops it — the dashboard
  # picker uses a separate undocumented endpoint. Every apply is
  # best-effort; visible drift is expected until Cloud exposes the
  # read side.
  color = try(each.value.color, null) != null ? each.value.color : lookup(var.default_env_colors, each.key, null)

  # v0.3.6 — PHP major version pin per env. Priority:
  #   1. environments[<env>].php_major_version — per-env override
  #   2. default_php_major_version_by_env[<env>] — module map
  #   3. default_php_major_version — workspace default
  # Cloud defaults to `"8.5"` when all three are null.
  #
  # Cloud's write field is `php_version` with a mandatory `:1`
  # suffix (e.g. `"8.4:1"`) — the provider encodes it internally.
  # Consumers only ever see the plain `"8.4"` shape. See
  # `figentra/laravel-cloud` v0.7.0's PHP-VERSION CONTRACT
  # ASYMMETRY docs on `internal/api/environments.go`.
  php_major_version = coalesce(
    try(each.value.php_major_version, null),
    lookup(var.default_php_major_version_by_env, each.key, null),
    var.default_php_major_version,
  )

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

# ────────────────────────────────────────────────────────────────
# Deployment — one per env when var.attach_deployment=true.
#
# Cloud AUTO-CREATES an "App" instance at environment creation with
# sensible defaults (flex-512mb, min_replicas=1, uses_octane=false,
# uses_scheduler=false). This module does NOT terraform-manage the
# auto-created instance today — a future `laravelcloud_env_instance_
# settings` resource will PATCH size / octane / scheduler on the
# existing instance instead of trying to create a duplicate.
#
# Horizon queue-type instances follow the same story: Cloud rejects
# a bare `type=queue` create ("At least one background process is
# required or the scheduler must be enabled") — the SDK's
# `CreateInstanceData` bundles `backgroundProcesses` in the same
# call, which the provider's v0.5.0 `laravelcloud_background_process`
# resource doesn't yet compose that way. Deferred.
#
# For now this module fires deployments ONLY — that's the critical
# path for "no deployments happening" that Phase B blocks on.
#
# The deployment depends implicitly on env creation via
# `environment_id`. `wait_for_completion=true` blocks apply until
# Cloud reports a terminal status.
# ────────────────────────────────────────────────────────────────

resource "laravelcloud_deployment" "this" {
  for_each = var.attach_deployment ? var.environments : {}

  environment_id      = laravelcloud_environment.envs[each.key].id
  redeploy_trigger    = var.redeploy_trigger
  wait_for_completion = var.deploy_wait_for_completion
  timeout_seconds     = var.deploy_timeout_seconds

  depends_on = [
    laravelcloud_bucket.buckets,
    laravelcloud_domain.domains,
  ]
}


# ────────────────────────────────────────────────────────────────
# Per-env network hardening — HSTS + rate-limit tier + robots tag
# + frame + content-type headers via
# `laravelcloud_environment_network_settings` (provider v0.5.0+).
#
# Every env in `var.environments` gets one settings resource unless
# the caller explicitly disables via `var.network_settings_by_env
# = null`. Values are computed per env from the merge of the
# workspace-default tier map and the per-env override map.
# ────────────────────────────────────────────────────────────────

locals {
  # Effective network-settings map — one entry per env declared in
  # `var.environments` that appears in the workspace tier map. When
  # both the default and override maps agree on a key, the override
  # wins per field.
  #
  # HCL's `lookup(map_of_object, key, {})` fails type-check when the
  # default value shape doesn't match the map element shape — so
  # `try(...)` is used instead. try() falls back to the second arg
  # when the first raises (missing key on a map of objects).
  network_settings_effective = {
    for env_key, _ in var.environments : env_key => merge(
      try(var.default_network_settings_by_env[env_key], null) == null ? {} : {
        cache_strategy                = try(var.default_network_settings_by_env[env_key].cache_strategy, null)
        response_headers_frame        = try(var.default_network_settings_by_env[env_key].response_headers_frame, null)
        response_headers_content_type = try(var.default_network_settings_by_env[env_key].response_headers_content_type, null)
        response_headers_robots_tag   = try(var.default_network_settings_by_env[env_key].response_headers_robots_tag, null)
        hsts_max_age                  = try(var.default_network_settings_by_env[env_key].hsts_max_age, null)
        hsts_include_subdomains       = try(var.default_network_settings_by_env[env_key].hsts_include_subdomains, null)
        hsts_preload                  = try(var.default_network_settings_by_env[env_key].hsts_preload, null)
        firewall_rate_limit_level     = try(var.default_network_settings_by_env[env_key].firewall_rate_limit_level, null)
        firewall_under_attack_mode    = try(var.default_network_settings_by_env[env_key].firewall_under_attack_mode, null)
      },
      try(var.network_settings_by_env[env_key], null) == null ? {} : {
        for k, v in {
          cache_strategy                = try(var.network_settings_by_env[env_key].cache_strategy, null)
          response_headers_frame        = try(var.network_settings_by_env[env_key].response_headers_frame, null)
          response_headers_content_type = try(var.network_settings_by_env[env_key].response_headers_content_type, null)
          response_headers_robots_tag   = try(var.network_settings_by_env[env_key].response_headers_robots_tag, null)
          hsts_max_age                  = try(var.network_settings_by_env[env_key].hsts_max_age, null)
          hsts_include_subdomains       = try(var.network_settings_by_env[env_key].hsts_include_subdomains, null)
          hsts_preload                  = try(var.network_settings_by_env[env_key].hsts_preload, null)
          firewall_rate_limit_level     = try(var.network_settings_by_env[env_key].firewall_rate_limit_level, null)
          firewall_under_attack_mode    = try(var.network_settings_by_env[env_key].firewall_under_attack_mode, null)
        } : k => v if v != null
      },
    )
    # Skip envs the tier map doesn't cover — the merged map has no
    # keys other than the null-collapse. Presence of the env in
    # var.default_network_settings_by_env is the enable signal.
    if contains(keys(var.default_network_settings_by_env), env_key)
  }
}

resource "laravelcloud_environment_network_settings" "envs" {
  for_each = local.network_settings_effective

  environment_id = laravelcloud_environment.envs[each.key].id

  cache_strategy                = try(each.value.cache_strategy, null)
  response_headers_frame        = try(each.value.response_headers_frame, null)
  response_headers_content_type = try(each.value.response_headers_content_type, null)
  response_headers_robots_tag   = try(each.value.response_headers_robots_tag, null)
  firewall_rate_limit_level     = try(each.value.firewall_rate_limit_level, null)
  firewall_under_attack_mode    = try(each.value.firewall_under_attack_mode, null)

  # HSTS nested block — send it ONLY when hsts_max_age is set to a
  # positive integer. When null or 0, the entire block is omitted so
  # Cloud drops the Strict-Transport-Security response header rather
  # than trying to send `max-age=0` (which HTTP semantics interpret as
  # "expire HSTS", but Cloud rejects the payload for missing
  # includeSubDomains on the same object).
  response_headers_hsts = coalesce(try(each.value.hsts_max_age, 0), 0) > 0 ? {
    max_age            = each.value.hsts_max_age
    include_subdomains = try(each.value.hsts_include_subdomains, true)
    preload            = try(each.value.hsts_preload, false)
  } : null
}
