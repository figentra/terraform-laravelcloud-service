# laravel-cloud-service module

Composes `figentra/laravel-cloud` provider resources into a shape a
Laravel Cloud service can consume in one HCL block.

## Purpose

Every Laravel Cloud service (identity, commerce, api, ai, ...) uses
this module once per env root to declare its Cloud footprint — the
application, its environments, and per-env database/cache/WS/bucket/
domain bindings.

Input shape mirrors a `<slug>.yaml` per-app manifest so an operator
moving from the Cloud dashboard / PHP CLI world to Terraform doesn't
have to re-learn the service contract.

## Status

**Phase 1 (0.1.0)** — creates the Cloud application only. Environments,
database schemas, caches, WS apps, buckets, domains land in Phase 2 as
the provider ships each resource type.

## Usage

```hcl
module "identity" {
  source  = "figentra/service/laravelcloud"
  version = "~> 0.1"

  name                         = "identity"
  organization_id              = local.orgs.default
  region                       = "us-east-1"
  source_control_provider_type = "github"
  repository                   = "my-org/identity-service"
  slack_channel                = "#deploys-identity"

  # Phase 2 inputs (declared but no-op'd today).
  environments = {
    dev = { branch = "develop" }
    stg = { branch = "staging", inherits = "dev" }
    prd = { branch = "main", inherits = "stg" }
  }

  database_cluster_id  = module.shared_db_cluster.id
  websocket_cluster_id = module.shared_ws_cluster.id

  buckets = [
    { name = "uploads", mode = "private" },
    { name = "public", mode = "public" },
  ]

  domains = {
    prd = "identity.example.com"
  }

  tags = local.common_tags
}

output "identity_id" {
  value = module.identity.application_id
}
```

## Inputs

See [`variables.tf`](variables.tf). Regenerated tables via `terraform-docs`
land in Phase 1.11 of the migration plan.

Required: `name`, `organization_id`.

Optional (Phase 1 respected): `region`, `source_control_provider_type`,
`repository`, `slack_channel`, `cluster_id`, `tags`.

Optional (Phase 2 declared, currently no-op): `environments`,
`database_cluster_id`, `websocket_cluster_id`, `buckets`, `domains`.

## Outputs

See [`outputs.tf`](outputs.tf).

Phase 1: `application_id`, `application_slug`, `application_name`, `region`, `created_at`.

Phase 2: `environment_ids`, `database_schema_ids`, `websocket_app_ids`, `bucket_names`.

## Cross-references

- [Provider docs](../../provider-laravel-cloud/README.md)
- [Migration plan](../../../.kiro/plans/2026-08-07-terraform-pivot-plan.md)
- [Laravel Cloud conventions](../../../.kiro/steering/laravel-cloud-conventions.md)
- [ADR-0080](../../../.docs/adr/0080-terraform-for-cloud-devops.md)

## Cloud auto-created `production` env — workspace playbook

Cloud automatically creates a `production` env on every fresh
application. Its ID is not returned by any resource this module
manages, and terraform's `laravelcloud_environment.envs[...]` will
collide with it if `var.environments` includes a `production` key.

**Workspace-canonical treatment**: rename the auto-created env from
`production` → `prd` so terraform can adopt it later via `import`
when the prd env root lands. The rename preserves the resource
(URLs, secrets, deployments) while freeing the `production` name for
future use.

Run once per new application (dev workstation, from workspace root):

```bash
doppler run --scope . --no-check-version -- bash -c '
API="https://cloud.laravel.com/api"
APP_ID="<the new laravelcloud_application.this.id>"
TOK="$LARAVEL_CLOUD_TOKEN"  # or ACADEMORIX for aliased provider

ENV_ID=$(curl -s -H "Authorization: Bearer $TOK" \
  "$API/applications/$APP_ID/environments" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(next((e[\"id\"] for e in d[\"data\"] if e[\"attributes\"][\"name\"] == \"production\"), \"\"))")

if [ -n "$ENV_ID" ]; then
  curl -s -X PATCH -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    -d "{\"name\":\"prd\"}" "$API/environments/$ENV_ID"
fi
'
```

Cloud's constraint: at least one env per app MUST be named "production"
OR "prd" (the primary deploy target). Deleting the "production" env
without a rename returns HTTP 422 "may not be deleted".

Codified 2026-08-10 during T16 of the enterprise day-1 completion —
8 workspace apps renamed to `prd` in one pass.

See also: `.kiro/plans/2026-08-08-enterprise-complete-plan.md` §T16.
