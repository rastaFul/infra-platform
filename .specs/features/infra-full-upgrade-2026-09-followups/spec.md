# SPEC: Follow-ups de infra-full-upgrade-2026-09 (D-2026-09-15-2/3)

## Status: APPROVED — 2026-09-15 (usuário respondeu D-2026-09-15-2 item a item, ver
DECISIONS.md D-2026-09-15-3)
## Created: 2026-09-15
## Owner: rodrigo

## Contexto

Ao fechar `infra-full-upgrade-2026-09`, registrei 9 dúvidas/pendências (D-2026-09-15-2). O usuário
respondeu todas. Esta spec cobre só os itens que exigem correção de código/config (3, 4, 7) — os
demais (1, 2, 5, 6, 8, 9) foram tratados fora desta spec (investigação registrada em DECISIONS.md,
ROADMAP.md atualizado, tooling instalado em `agents-harness`, fix pontual de dashboard aplicado
direto por ser trivial e já verificado).

## Tasks

### T1 — `rasta-slo.json`: corrigir `fieldConfig.overrides` do painel "Downtime Events"
Achado: painel usa `rawSql` (SQL, pós-migração D3) mas os `overrides` ainda referenciam nomes de
coluna do Flux antigo (`_time`, `_value`) — a query real retorna `time` e `value` (aliased de
`result_code AS value`). Regressão cosmética (nome de coluna errado no display), painel continua
funcionando, só sem o rename bonito de coluna.

Fix: trocar `matcher.options` de `_value`→`value` e `_time`→`time` nos 2 overrides afetados
(`probe`→"Service" já está correto, não mexer). Arquivo:
`platform/dashboards/rastafinancas/rasta-slo.json`.

Gate: `docker restart platform-grafana` (ou aguardar polling do provisioning), confirmar via
`/api/dashboards/uid/...` que os overrides batem com as colunas reais retornadas por
`/api/ds/query` pro mesmo painel.

### T2 — Vault: criar tenant `platform` (KV v2) + AppRole, empurrar `platform/.env`
Achado: `INFLUXDB3_ADMIN_TOKEN` (e por extensão TODOS os segredos platform-level —
`GRAFANA_ADMIN_PASSWORD`, `GLITCHTIP_SECRET_KEY`, `GLITCHTIP_DB_PASSWORD`, `INFLUXDB_ADMIN_PASSWORD`)
só existem em `platform/.env`, nunca foram levados pro Vault como os 4 tenants de produto
(microgrow/rastafinancas/vetcare/artists) já são. Gap arquitetural, não só do token do InfluxDB 3.

Fix:
1. Criar `platform/vault/policies/platform.hcl` (read-only em `secret/data/platform/*`, mesmo
   padrão dos outros 4 arquivos em `platform/vault/policies/`).
2. Adicionar `platform` ao array `PROJECTS` em `scripts/vault-init.sh` (hoje só tem
   `vetcare rastafinancas microgrow artists`) — cria a policy + AppRole igual aos outros.
3. Rodar `vault-init.sh` (idempotente, `create_approle`/`apply_policy` já checam se existe antes de
   recriar) pra aplicar a policy+approle de `platform`.
4. Rodar `./scripts/vault-push-env.sh platform platform/.env` pra popular
   `secret/data/platform/env` com o conteúdo real.
5. Gate: `vault kv get secret/platform/env` confirma os campos reais (incluindo
   `INFLUXDB3_ADMIN_TOKEN`) batendo com `platform/.env`. `vault auth list` confirma approle
   `platform` registrado.

Não muda o design existente ("`.env` continua sendo o que a app lê" — Vault é canônico/auditoria,
não acoplamento de boot, mesma decisão já registrada nas sessões anteriores). Isso só estende o
padrão dos 4 tenants pro nível platform.

### T3 — Gates de segurança finais: gitleaks working-tree + trivy_config Dockerfile.sandbox
Dois achados distintos, dois fixes distintos:

**T3a — gitleaks falso-positivo em `.env` gitignorado**: `skills/security-gates/scripts/
run-security-gates.sh` roda `gitleaks detect --no-git` (varredura de filesystem puro, ignora
`.gitignore`) — sinaliza segredos em arquivos que NUNCA seriam commitados. Fix: antes de rodar o
gitleaks, gerar uma lista dos arquivos gitignorados no diretório (`git ls-files --others --ignored
--exclude-standard`, só se `$DIR` for um repo git) e passar como `[allowlist] paths` num arquivo de
config temporário do gitleaks (`--config`), preservando a varredura de tudo mais. Fallback: se não
for repo git, comportamento atual (sem allowlist) é mantido, sem regressão.

**T3b — trivy_config HIGH (DS-0002) em `.harness-sandbox/docker/Dockerfile.sandbox`**: falta `USER`
não-root. **Já corrigido nesta sessão** (fora da ordem desta spec, por conveniência — o Dockerfile
já estava aberto pro fix do tflint quebrado, ver nota abaixo) — reaproveita o usuário `node`
(uid 1000) que a imagem base `node:20-alpine` já tem, compatível com o bind-mount de
`sandbox-run.sh`. Canônico em `agents-harness/docker/Dockerfile.sandbox`, sincronizado pra
`infra-platform/.harness-sandbox/docker/Dockerfile.sandbox` (cópia idêntica, mesmo padrão de antes).

Nota: durante a correção do T3b, achado bug real não relacionado: `terraform-linters/tflint`
removeu `install_linux.sh` do repo em 2026-09-12 (3 dias antes desta sessão) — o `RUN curl .../
install_linux.sh | bash` do Dockerfile.sandbox e do `install-gate-tools.sh` (item 8, ver
DECISIONS.md) quebravam com 404. Corrigido nos dois lugares (download direto do zip do release).

Gate T3: `bash skills/security-gates/scripts/run-security-gates.sh` PASS (gitleaks não sinaliza
mais os `.env` gitignorados, mas AINDA sinaliza se algo git-tracked tiver segredo real — testar
com um segredo de teste staged, revertido depois). `trivy config .harness-sandbox/docker/
Dockerfile.sandbox` PASS (0 HIGH/CRITICAL). `docker build` real do `Dockerfile.sandbox` com o novo
`USER node` — confirma que build completa e as ferramentas continuam executáveis pelo usuário novo
(smoke test: `terraform version`, `trivy version`, `helm plugin list` como `node`).

## Done Criteria
- T1: dashboard `rasta-slo.json` com overrides corretos, confirmado via API real do Grafana.
- T2: `secret/data/platform/env` existe no Vault com todos os campos de `platform/.env`, policy +
  AppRole `platform` registrados, confirmado via `vault kv get`/`vault auth list` reais.
- T3: `run-security-gates.sh` não falsea mais por `.env` gitignorado (mas continua pegando segredo
  real de verdade, testado); `Dockerfile.sandbox` builda com `USER node`, ferramentas smoke-tested
  funcionando como não-root; sincronizado em `agents-harness` (canônico) e `infra-platform`
  (`.harness-sandbox/`, cópia).
- Todos os 3 gates rodados de verdade, registrados em `.specs/audit/execution.md`.
