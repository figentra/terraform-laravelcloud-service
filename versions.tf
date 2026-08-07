# Terraform + provider version constraints for the laravel-cloud-service
# module. Every module in the workspace declares its own versions.tf so
# consumers can compose modules with differing provider versions safely.
#
# Terraform 1.9+ is required for the `import { }` declarative block syntax
# used during Phase 4 (state import). Older versions fall back to the
# imperative `terraform import` command which doesn't compose with modules.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    laravelcloud = {
      source  = "stackra/laravel-cloud"
      version = "~> 0.1"
    }
  }
}
