#cloud-config
# Bootstraps Docker + Coolify on first boot. Idempotent-ish (cloud-init
# runs once per instance by design — re-running requires `cloud-init clean`
# + reboot, not expected in normal operation).
package_update: true
package_upgrade: true

packages:
  - ca-certificates
  - curl
  - gnupg
  - ufw

runcmd:
  # ── Docker (official convenience script — supports arm64/Ubuntu 24.04) ──
  - curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  - sh /tmp/get-docker.sh
  - systemctl enable --now docker
  - usermod -aG docker ubuntu

  # ── Firewall: SSH only, everything else denied inbound. Security list
  #    (Terraform) already restricts at the OCI network level — this is
  #    defense in depth at the host level too. ─────────────────────────
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw --force enable

  # ── Coolify (official installer — Ubuntu 24.04 arm64 supported) ─────
  - curl -fsSL https://cdn.coollabs.io/coolify/install.sh -o /tmp/coolify-install.sh
  - bash /tmp/coolify-install.sh

final_message: "oci-free instance ready after $UPTIME seconds. Docker + Coolify installed. Next: infra-platform docs/how-to/provision-oracle-free-tier.md steps 5-8 (tunnel relocation, Coolify config, platform stack deploy)."
