# How-To: Add a Cloudflare Hostname

**When:** New service needs a public URL, or moving a service to a new origin.

## Via Terraform (recommended)

```hcl
# In terraform/main.tf (or project-specific module call)
module "dns_myservice" {
  source   = "./modules/cloudflare-dns"
  zone_id  = var.cloudflare_zone_id
  hostname = "myservice.rastaful.dev"
  origin   = "<alb-dns-or-tunnel-id>"
  proxied  = true
}
```

```bash
terraform plan -var-file=environments/production.tfvars -target=module.dns_myservice
terraform apply -var-file=environments/production.tfvars -target=module.dns_myservice
```

## Via Cloudflare Tunnel (local/VPS, no public IP)

```bash
# Create tunnel (one-time)
cloudflared tunnel create myservice

# Add hostname to tunnel config (~/.cloudflared/config.yml):
ingress:
  - hostname: myservice.rastaful.dev
    service: http://localhost:<port>
  - service: http_status:404

# Route DNS
cloudflared tunnel route dns myservice myservice.rastaful.dev

# Start tunnel
cloudflared tunnel run myservice
```

## Verify

```bash
curl -I https://myservice.rastaful.dev
# Expect: HTTP/2 200, server: cloudflare
```
