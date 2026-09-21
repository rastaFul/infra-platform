# How to Activate Resend SMTP for Grafana Alerting

**Status: wired up, not activated.** Grafana's contact points (`platform-critical`/`platform-warning`/`platform-info` in `platform/grafana/provisioning/alerting/contact-points.yaml`) send email through Grafana's own SMTP client, configured via `GF_SMTP_*` env vars in `platform/docker-compose.yml`. Before 2026-09-17 this pointed at Gmail with **no credential set at all** (`GF_SMTP_USER`/`GF_SMTP_PASSWORD` never existed) — every alert email since alerting was first provisioned (2026-08-27) failed with `530 5.7.0 Authentication Required`, silently, because nobody was watching the Grafana container logs (see D-2026-09-01-1, D-2026-09-17-2). Switched to Resend per D-2026-09-09-5. This doc is the step this agent won't take on your behalf (creating a third-party account) — do it yourself when ready.

## 1. Create a Resend account

https://resend.com — free tier: 3,000 emails/month, 100/day, no credit card required to start (unlike Cloudflare R2, which is why this one wasn't already blocked on a "no cost" objection like R2 was).

## 2. Verify the `rastaful.dev` domain

Dashboard → Domains → Add Domain → `rastaful.dev`. Resend gives you DNS records (SPF/DKIM, typically TXT + CNAME) to add. Since DNS for `rastaful.dev` is already on Cloudflare (used for the tunnel, see `tunnel/`), add them in the Cloudflare dashboard → DNS. Wait for Resend to show the domain as verified (usually minutes, can take up to 24h for DNS propagation).

Without a verified domain, Resend only lets you send to your own account's email address from `onboarding@resend.dev` — fine for a first smoke test, not for `noreply@rastaful.dev` as configured in `.env`.

## 3. Generate an API key

Dashboard → API Keys → Create API Key. Scope: **Sending access**, restricted to the `rastaful.dev` domain if given the option. Copy it once — Resend doesn't show it again.

## 4. Set `SMTP_PASSWORD` in `platform/.env`

```bash
SMTP_HOST=smtp.resend.com:587
SMTP_USER=resend
SMTP_PASSWORD=re_your_real_api_key_here
SMTP_FROM=noreply@rastaful.dev
```

`SMTP_HOST`/`SMTP_USER`/`SMTP_FROM` are already set to these values as of D-2026-09-17-2 — only `SMTP_PASSWORD` is missing (deliberately left empty, never guess/fabricate a credential).

## 5. Recreate Grafana to pick up the new env var

```bash
cd /home/rodrigo/projects/infra-platform/platform
docker compose up -d --force-recreate grafana
```

(`docker compose restart` is not reliable here — a known WSL2/Docker Desktop bind-mount staleness bug has bitten this exact stack before, see D-2026-09-09-1 and D-2026-09-17-2. `--force-recreate` sidesteps it.)

## 6. Verify for real — don't trust "no error on boot"

Grafana only tries to send on an actual alert transition (Normal→Alerting or resolve), so boot succeeding proves nothing. Force a real send.

**Update 2026-09-21**: the old `/api/alertmanager/grafana/config/api/v1/receivers/test` endpoint was removed in Grafana 13.2.1 (`410 Gone`, "This endpoint has been removed"). Use the new k8s-style app API instead. First find the receiver's `metadata.name` (base64 of the title, not the `uid` field — GET-by-uid 404s):

```bash
source platform/.env
curl -s -u "admin:${GRAFANA_ADMIN_PASSWORD}" \
  http://127.0.0.1:3010/apis/notifications.alerting.grafana.app/v1beta1/namespaces/default/receivers \
  | python3 -c "import json,sys; d=json.load(sys.stdin); [print(r['spec']['title'], r['metadata']['name']) for r in d['items']]"
```

Then test with the receiver's actual integration (type/uid/settings — copy from the receiver's `spec.integrations[0]`, e.g. via `GET .../receivers/<name>`), body shape is `{integration, alerts}`, **not** `{receiver, alert}` like the old API:

```bash
curl -s -u "admin:${GRAFANA_ADMIN_PASSWORD}" -X POST \
  "http://127.0.0.1:3010/apis/notifications.alerting.grafana.app/v1beta1/namespaces/default/receivers/<base64-name>/test" \
  -H "Content-Type: application/json" \
  -d '{
    "integration": {"type":"email","uid":"critical-email","settings":{"addresses":"rodrigob.dev@gmail.com","singleEmail":false,"subject":"test"}},
    "alerts": [{"annotations":{"summary":"SMTP test"},"labels":{"severity":"critical"}}]
  }'
```

`{"status":"success","duration":"...ms"}` with HTTP 200 means Grafana actually completed the SMTP transaction (a multi-second duration confirms a real network round-trip, not an instant fake pass). Then check the actual inbox (`rodrigob.dev@gmail.com`, per `contact-points.yaml`) and `docker logs platform-grafana | grep -i smtp` for either a successful send log or the real error (auth, DNS, rate limit) — same "no external verification, no trust" rule as everything else in this repo.
