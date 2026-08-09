/**
 * @file variables.tf
 * @description Input variables for the laravel-cloud-service module.
 *
 *   The input shape mirrors `.kiro/cloud/apps/<slug>.yaml` (the
 *   legacy workspace-tracked manifest) so operators moving from the
 *   PHP CLI to Terraform have a mechanical 1:1 translation.
 *
 *   v0.4.0 (Cloud API v2 alignment):
 *     - `organization_id` kept as a deprecated no-op variable so
 *       existing consuming HCL doesn't break at plan-time. Callers
 *       can drop it on the next major module bump.
 *     - Cache: added cache_type / cache_auto_upgrade_enabled /
 *       cache_is_public / cache_eviction_policy.
 *     - Bucket: object schema changed — mode → visibility, region →
 *       jurisdiction, added key_permission. Old fields dropped from
 *       the object type.
 *     - Domain: added domain_defaults object for www_redirect /
 *       verification_method / cloudflare_strategy.
 *     - Websocket: max_connections is now cluster-scoped; the
 *       module no longer accepts a per-env override for it (set on
 *       the shared websocket_cluster resource).
 *
 * Cross-refs:
 *   main.tf              resource composition using these inputs
 *   outputs.tf           values downstream consumers bind
 *   versions.tf          figentra/laravel-cloud provider pin
 */

variable "name" {
  description = <<-DESC
    Service slug — matches the workspace slug from
    `.kiro/cloud/apps/<slug>.yaml`. Used as the Cloud application
    name AND as the prefix for every child resource
    (`<name>-<env>`).

    Convention: lowercase-kebab, starts with a letter. Examples:
    `my-service`, `my-api`, `my-notifications`.
  DESC
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase, start with a letter, and contain only letters, digits, and dashes."
  }
}

# ────────────────────────────────────────────────────────────────
# Legacy — kept as a no-op for backward compat with consuming HCL.
# ────────────────────────────────────────────────────────────────

variable "organization_id" {
  description = <<-DESC
    DEPRECATED. Cloud API v2 removed organization scoping from every
    resource — the token itself carries the org scope. This variable
    is accepted for backward compat with existing consuming HCL but
    is not used. Drop from callers on the next module major bump.
  DESC
  type        = string
  default     = null
}

# ────────────────────────────────────────────────────────────────
# Application
# ────────────────────────────────────────────────────────────────

variable "region" {
  description = <<-DESC
    Deploy region. Immutable post-create — changing the region
    forces a destroy + recreate of every child resource.

    Example: `us-east-1`, `eu-west-1`.
  DESC
  type        = string
  default     = "us-east-1"
}

variable "source_control_provider_type" {
  description = <<-DESC
    Source control provider — one of `github`, `gitlab`, `bitbucket`.
    Immutable post-create. Determines the OAuth flow Cloud uses to
    poll for pushes + trigger deploys.
  DESC
  type        = string
  default     = "gitlab"

  validation {
    condition     = contains(["github", "gitlab", "bitbucket"], var.source_control_provider_type)
    error_message = "source_control_provider_type must be one of: github, gitlab, bitbucket."
  }
}

variable "repository" {
  description = <<-DESC
    Repository identifier in `owner/repo` shape (e.g.
    `my-org/backend-service`). REQUIRED — Cloud API v2 rejects apps
    without one.
  DESC
  type        = string
}

variable "root_directory" {
  description = <<-DESC
    Sub-path within the repo Cloud builds from. Empty / null when
    building from the repo root. Required for monorepos where the
    Laravel app is nested under a subdirectory.
  DESC
  type        = string
  default     = null
}

variable "slack_channel" {
  description = <<-DESC
    Slack channel for deploy notifications. Example: `#deploys`.
    Null skips wire-up; Cloud won't post deploy notices to Slack.
  DESC
  type        = string
  default     = null
}

variable "cluster_id" {
  description = <<-DESC
    Deploy cluster ID (opaque). Optional — Cloud picks a default
    when unset. Consumers set this when the workspace uses a
    dedicated cluster for isolation.
  DESC
  type        = string
  default     = null
}

# ────────────────────────────────────────────────────────────────
# Per-environment configuration
# ────────────────────────────────────────────────────────────────

variable "environments" {
  description = <<-DESC
    Per-environment configuration. Keys: env slug (`dev`/`stg`/`prd`
    typically, plus optional preview slugs). Values: env-specific
    config translated to `laravelcloud_environment` + cache + ws_app
    + bucket resources.

    Note: `websocket_max_connections` and `inherits` fields are
    deprecated no-ops (max_connections is now on the cluster;
    inherits was removed from Cloud API v2).

    v0.4.5 addition: optional `color` (blue/green/orange/purple/red/
    yellow/cyan/gray). Falls back to `var.default_env_colors[<env>]`
    when the env doesn't specify one.

    Example:
      environments = {
        dev = { branch = "develop", variables = { APP_DEBUG = "true" }, cache_size = "cache-1gb" }
        prd = { branch = "main",    variables = { APP_DEBUG = "false" }, cache_size = "cache-4gb" }
      }
  DESC
  type = map(object({
    branch                    = optional(string)
    variables                 = optional(map(string), {})
    inherits                  = optional(string) # DEPRECATED no-op
    cache_size                = optional(string, "cache-1gb")
    websocket_max_connections = optional(number) # DEPRECATED no-op
    color                     = optional(string)
  }))
  default = {}
}

variable "default_env_colors" {
  description = <<-DESC
    Default env color palette matching the workspace convention:
    `dev=green` (OK), `stg=orange` (care), `prd=red` (danger).
    Preview envs default to purple. Caller overrides individual envs
    via `environments[<env>].color`.
  DESC
  type        = map(string)
  default = {
    dev = "green"
    stg = "orange"
    prd = "red"
  }
}

# ────────────────────────────────────────────────────────────────
# Shared cluster bindings
# ────────────────────────────────────────────────────────────────

variable "database_cluster_id" {
  description = <<-DESC
    Shared database cluster ID this service's schemas live in.
    Consumed by the schema resource when `attach_database=true`.
    Null when the service doesn't need a database.
  DESC
  type        = string
  default     = null
}

variable "attach_database" {
  description = <<-DESC
    When true, provision one `laravelcloud_database_schema` per env
    under `database_cluster_id`.

    MUST be plan-time-known — do NOT derive from a resource output
    (that yields "known after apply" which breaks `for_each` key
    resolution). Callers set this bool statically alongside passing
    `database_cluster_id`.
  DESC
  type        = bool
  default     = false
}

# ────────────────────────────────────────────────────────────────
# Cache configuration
# ────────────────────────────────────────────────────────────────

variable "attach_cache" {
  description = <<-DESC
    When true, provision a per-env Valkey/Redis cache. Size comes
    from `environments[<env>].cache_size`. Plan-time-known — see
    `attach_database` for the rationale.
  DESC
  type        = bool
  default     = false
}

variable "cache_type" {
  description = <<-DESC
    Cache backend — one of `upstash_redis`, `laravel_valkey`,
    `aws_elasticache_redis`, `aws_elasticache_valkey`. Immutable
    post-create. Defaults to Laravel Valkey (Cloud-managed).
  DESC
  type        = string
  default     = "laravel_valkey"

  validation {
    condition     = contains(["upstash_redis", "laravel_valkey", "aws_elasticache_redis", "aws_elasticache_valkey"], var.cache_type)
    error_message = "cache_type must be one of: upstash_redis, laravel_valkey, aws_elasticache_redis, aws_elasticache_valkey."
  }
}

variable "cache_auto_upgrade_enabled" {
  description = <<-DESC
    When true, Cloud auto-upgrades the underlying cache software
    (patch versions). Recommended `true` — patch versions are safe
    and the alternative is a manual op debt.
  DESC
  type        = bool
  default     = true
}

variable "cache_is_public" {
  description = <<-DESC
    When true, the cache is publicly reachable. Prefer `false` +
    VPC binding — the default. Only override when the workspace
    has a bespoke ingress pattern.
  DESC
  type        = bool
  default     = false
}

variable "cache_eviction_policy" {
  description = <<-DESC
    Redis eviction policy — one of `allkeys-lru`, `noeviction`,
    `volatile-lru`, `allkeys-random`, `volatile-random`,
    `volatile-ttl`, `allkeys-lfu`, `volatile-lfu`. Null = Cloud
    default (`allkeys-lru`).
  DESC
  type        = string
  default     = null
}

# ────────────────────────────────────────────────────────────────
# WebSocket configuration
# ────────────────────────────────────────────────────────────────

variable "websocket_cluster_id" {
  description = <<-DESC
    Shared WebSocket cluster ID. Consumed by the WS-app resource
    when `attach_websocket=true`. Null when the service doesn't
    need Reverb.
  DESC
  type        = string
  default     = null
}

variable "attach_websocket" {
  description = <<-DESC
    When true, provision one `laravelcloud_websocket_app` per env
    on `websocket_cluster_id`, and bind the env to it via
    `websocket_application_id`. Plan-time-known bool — see
    `attach_database` for the rationale.
  DESC
  type        = bool
  default     = false
}

# ────────────────────────────────────────────────────────────────
# Buckets + domains
# ────────────────────────────────────────────────────────────────

variable "buckets" {
  description = <<-DESC
    S3-compatible buckets this service owns. Each entry creates one
    bucket PER ENV. Name pattern: `<service>-<bucket>-<env>` (e.g.
    `my-service-uploads-prd`). Every bucket ships with a root access
    key named `<service>-<bucket>-<env>-root` at `read_write`
    permission by default; override per bucket via `key_permission`.

    Each entry:
      - name           — bucket short-name (e.g. `uploads`, `backups`)
      - jurisdiction   — data-residency zone (`us`/`eu`/`me`/...)
      - visibility     — `private` (default) or `public`
      - key_permission — `read_write` (default) or `read_only`
  DESC
  type = list(object({
    name           = string
    jurisdiction   = optional(string)               # us / eu / me / ...
    visibility     = optional(string, "private")    # private / public
    key_permission = optional(string, "read_write") # read_only / read_write
  }))
  default = []
}

variable "default_bucket_jurisdiction" {
  description = <<-DESC
    Default jurisdiction (data-residency zone) for buckets that
    don't specify one. Example: `us`, `eu`, `me`.
  DESC
  type        = string
  default     = "us"
}

variable "domains" {
  description = <<-DESC
    Custom domains bound to this service's environments. Map shape:
    `{ <env> = "<hostname>" }` — one entry per env that should
    expose a custom-domain endpoint.

    Example:
      domains = {
        dev = "api.dev.example.com"
        stg = "api.stg.example.com"
        prd = "api.example.com"
      }
  DESC
  type        = map(string)
  default     = {}
}

variable "domain_defaults" {
  description = <<-DESC
    Domain-binding defaults applied to every domain in `var.domains`.
    Consumers override individual fields per env root if needed.

    Valid values per the Cloud SDK's DomainRedirect /
    DomainVerificationMethod / DomainCloudflareStrategy enums:
      www_redirect        : "root_to_www" | "www_to_root"
      verification_method : "pre_verification" | "real_time"
      cloudflare_strategy : "none" | "dns" | "dns_proxy"
  DESC
  type = object({
    www_redirect        = optional(string, "www_to_root") # www_to_root: hits to www.* redirect to naked subdomain
    verification_method = optional(string, "real_time")   # real_time: verify at request time (vs pre_verification)
    cloudflare_strategy = optional(string, "dns_proxy")   # dns_proxy: proxy through Cloudflare (orange cloud)
  })
  default = {}
}

variable "tags" {
  description = <<-DESC
    Free-form tags for cost attribution + audit. Currently
    informational — Cloud API v2 doesn't expose a tags field yet.
    Consumers still author the map so the intent survives when the
    API gains support.
  DESC
  type        = map(string)
  default     = {}
}

# ────────────────────────────────────────────────────────────────
# Nightwatch (Laravel APM) integration
#
# On Laravel Cloud, Nightwatch's auto-integration provisions
# NIGHTWATCH_TOKEN + runs the agent as a background process
# automatically once the "Enable Nightwatch" toggle is set per
# app (Cloud UI or provider PR — Wave 14). This module ONLY
# manages the env-var overrides consumers usually want:
#
#   - NIGHTWATCH_ENABLED per env (disable in dev, enable in stg/prd)
#   - NIGHTWATCH_SAMPLING_RATE per env (10% in dev, 100% in prd)
#   - NIGHTWATCH_REDACT_HEADERS (workspace-uniform default)
#   - NIGHTWATCH_DEPLOY tracking left to Cloud (auto per
#     nightwatch.laravel.com/docs/deployments §Automatic Setup —
#     Cloud sends release ref/name/URL on every deploy).
#
# Consumers opt out entirely via nightwatch.enabled_in = [].
# ────────────────────────────────────────────────────────────────

variable "nightwatch" {
  description = <<-DESC
    Nightwatch integration knobs. Applied as env vars on each Cloud
    environment. Set `enabled_in = []` to skip entirely.

    Fields:
      enabled_in           : env slugs where `NIGHTWATCH_ENABLED=true`.
                             Default: `stg` + `prd` (dev opts out for
                             cost).
      sampling_rate_by_env : `NIGHTWATCH_SAMPLING_RATE` per env.
                             Default: dev=0.1, stg=0.5, prd=1.0.
      redact_headers       : `NIGHTWATCH_REDACT_HEADERS` comma-separated
                             list. Default matches OneUptime + Cloud's
                             own workspace conventions.
      log_stack            : When set, adds `LOG_STACK` env var so
                             Laravel ships to both Cloud Logs +
                             Nightwatch (per
                             cloud.laravel.com/docs/knowledge-base/nightwatch-on-cloud).
                             Default: null = leave `LOG_STACK` alone.
  DESC
  type = object({
    enabled_in           = optional(list(string), ["stg", "prd"])
    sampling_rate_by_env = optional(map(number), {})
    redact_headers       = optional(string, "cookie,authorization,x-api-key,x-service-identity,x-doppler-token")
    log_stack            = optional(string, null)
  })
  default = {}
}
