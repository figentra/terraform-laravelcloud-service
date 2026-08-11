/**
 * @file versions.tf
 * @description Terraform + provider version constraints for the
 *   laravel-cloud-service module.
 *
 *   Every module in the workspace declares its own versions.tf so
 *   consumers can compose modules with differing provider versions
 *   safely.
 *
 *   Terraform 1.9+ is required for the `import { }` declarative
 *   block syntax used during Phase 4 (state import). Older versions
 *   fall back to the imperative `terraform import` command which
 *   doesn't compose with modules.
 *
 * Cross-refs:
 *   main.tf                                     provider consumer
 *   laravel-cloud-static-site/versions.tf       sibling — same pin
 */

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    laravelcloud = {
      source = "figentra/laravel-cloud"
      # v0.7.0 required for writable `php_major_version` attribute on
      # `laravelcloud_environment`. Pre-v0.7.0 providers reject the
      # attribute plan-time; the module's `laravelcloud_environment.envs`
      # resource block sets it unconditionally.
      version = "~> 0.7"
    }
  }
}
