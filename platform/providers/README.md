# Providers Directory

**NOTE**: This directory is intentionally empty/disabled.

## Architecture Decision

**Crossplane providers are managed by Terraform**, not ArgoCD.

- **Terraform manages**: Crossplane core + UPJET AWS providers (provider-upjet-aws-*)
- **ArgoCD manages**: XRDs, Compositions, ProviderConfigs (via `dev-platform-crossplane` app)

## Why?

Terraform provides better lifecycle management for Crossplane installation and provider dependencies.
ArgoCD is better suited for managing the platform abstractions (XRDs/Compositions) built on top of Crossplane.

## Disabled Files

- `aws-provider.yaml.disabled` - Native Upbound providers (conflicts with Terraform's UPJET providers)

If you need to switch to ArgoCD-managed providers in the future, see `docs/CROSSPLANE-IRSA-SETUP.md`.
