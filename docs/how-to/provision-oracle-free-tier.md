# How to Provision the `oci-free` Environment

**Status: DRAFT — prerequisites confirmed, Terraform module (`terraform/modules/oci-compute/`) not yet written.**
This doc will be completed with exact commands once the module lands. Recorded now so the manual prerequisites (which can't be scripted) aren't lost between sessions.

See ADR 005 (environment strategy), ADR 007 (why Oracle), ADR 008 (state backend).

## Prerequisites (manual, one-time, cannot be automated)

1. **Oracle Cloud account.** Sign up at [cloud.oracle.com](https://cloud.oracle.com) — requires identity/card verification for the free tier (no charge occurs on the Always Free shapes). Pick a **region that isn't US** for the ARM free shape — Frankfurt, Singapore, or Tokyo provision reliably; US regions frequently report "Out of host capacity" for Ampere A1.
2. **OCI API key for Terraform.** After the account exists: `oci setup config` (OCI CLI) or generate an API signing key from the OCI Console (Profile → API Keys). This produces a private key + fingerprint that the Terraform `oci` provider needs to authenticate. Do **not** commit the private key — store it outside the repo, referenced via environment variable / Terraform Cloud variable set (ADR 008).
3. **Terraform Cloud account.** Sign up at [app.terraform.io](https://app.terraform.io) (free), create an organization, generate an API token (`terraform login`). This is the remote state backend for every environment, not just `oci-free` (ADR 008).

## Planned steps (once the Terraform module exists)

1. `terraform/environments/oci-free/` — new tfvars + backend config pointing at the Terraform Cloud workspace.
2. `terraform/modules/oci-compute/` — VCN, subnet, security list (only 22/tcp from your IP + nothing else public — the VM has no public services, Cloudflare Tunnel handles ingress), Ampere A1 compute instance (2 OCPU / 12GB, ADR 007), boot volume, `cloud-init` user-data that installs Docker + Coolify non-interactively on first boot.
3. `terraform plan -var-file=environments/oci-free/terraform.tfvars` — review before apply.
4. `terraform apply` — provisions the VM, Coolify comes up automatically via cloud-init.
5. Point `cloudflared` (currently running under PM2 on this WSL2 machine, see `~/.cloudflared/config.yml`) at the new VM — relocate the tunnel connector, not the DNS/domain (no DNS changes needed).
6. Configure Coolify: connect it to each app repo (GitHub), point it at the reusable CD workflow's published image (ADR 006).
7. Deploy the shared platform stack (`infra-platform/platform/docker-compose.yml`) via Coolify — same file already validated locally (Batch 1 gate, 2026-08-27).
8. Validate: `/health` on each app, Grafana reachable, Vault `status` healthy, Cloudflare Tunnel routing correctly.

## Explicitly out of scope for `oci-free`

- `vetcare-postgres_test` (test-only DB) — stays local, no reason to run it on the free tier.
- Any service not already gated (docker build PASS) locally — nothing untested gets deployed, per ADR 005's promotion pipeline.
