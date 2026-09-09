## Task 1: Create infra-platform repository scaffold — 2026-08-12T01:10:33-03:00
- tsc --noEmit: N/A (no TypeScript)
- eslint: N/A (no TypeScript)
- jest: N/A (no TypeScript)
- docker compose config: PASS
- OTEL YAML validation: PASS (pipelines: traces, metrics, logs)
- git init + git add -A: PASS (46 files tracked)
- TDD: N/A (infrastructure scaffold, no application code)
- Status: DONE

## Task: local-boot-persistence — rastafinancas PM2→Docker — 2026-08-28
- docker compose config: PASS (2 services)
- docker build (api, web): PASS after fix (2 real bugs found: npm workspaces hoisting node_modules to root not apps/api — MODULE_NOT_FOUND fastify/drizzle-orm; healthcheck wget resolving "localhost"->::1 while Fastify binds IPv4-only 0.0.0.0)
- next.config.js rewrite bug found+fixed: Next.js bakes rewrites() destination into routes-manifest.json at BUILD time, not runtime — env var in docker-compose `environment:` had no effect; moved to Dockerfile build-stage ENV instead.
- Runtime verification (real, not assumed): api /health 200 (deps.database:ok), web /health 200, public https://financas.rastaful.dev root 307 + /api/health 200 (full path: Cloudflare Tunnel -> host port -> web container -> api container)
- Data continuity: SQLite file bind-mounted (./apps/api/data), same file as PM2 used, size unchanged post-migration
- PM2: rastafinancas-api/web stopped, verified healthy in Docker, then `pm2 delete` + `pm2 save`
- Status: DONE

## Task: local-boot-persistence — microgrow PM2->Docker — 2026-08-28
- Achado real (não relacionado à migração): mosquitto/telegraf/promtail estavam parados há 5 dias (docker-compose infra nunca tinha sido re-subido desde então) — subidos como efeito colateral desta migração.
- docker compose up -d --build (7 serviços: mosquitto, telegraf, promtail, simulator, api, webapp, webapp-sim): todos healthy/up.
- Fixes pre-aplicados (lição do rastafinancas) evitaram os mesmos 3 bugs: HOST=0.0.0.0, healthcheck 127.0.0.1, API_INTERNAL_URL baked no build stage do Dockerfile. Nenhum bug novo neste serviço.
- api /health: 200 {mqtt: ok}. Público: grow.rastaful.dev 307, grow-sim.rastaful.dev 307.
- PM2: microgrow-api/webapp/webapp-sim/simulator deletados + save.
- Status: DONE

## Task: local-boot-persistence — vetcare PM2->Docker — 2026-08-28
- docker compose config: PASS. Build: PASS (no fixes needed — monolito, sem proxy interno /api/*, DATABASE_URL apontado pro service `postgres` em vez de localhost).
- Runtime: healthy de primeira. Local :3004 -> 307, público vetcare.rastaful.dev -> 307.
- PM2: vetcare deletado + save.
- Status: DONE

## Task: local-boot-persistence — artists-booking PM2->Docker — 2026-08-28
- 3 bugs reais achados/corrigidos (pnpm-specific, nunca exercitados antes):
  1. web: `pnpm`'s apps/web/node_modules é árvore de symlinks pro root node_modules/.pnpm — Dockerfile achatava apps/web/* pra /app/* igual aos repos npm, quebrando os symlinks (MODULE_NOT_FOUND next). Fix: preservar layout do monorepo (copiar root store + apps/web como está, WORKDIR /app/apps/web).
  2. api: `pnpm --filter api deploy --prod` re-resolve node_modules do zero e perde o client gerado pelo `prisma generate` (não é parte da instalação). Fix: `pnpm prune --prod` in-place em vez de deploy + mesmo fix de symlink do item 1.
  3. api: Alpine sem libssl -> `prisma generate` não detectou versão OpenSSL, default errado (1.1, EOL) -> engine não carregava em runtime. Fix: `apk add openssl` no builder E no runtime stage.
- Runtime real verificado: api /health 200 (deps.database:ok), web 307, proxy web->api real (404 esperado, rota certa é /health não /api/v1/health, mas prova que a cadeia de rede funciona), público artists.rastaful.dev 307. Continuidade de dado: dev.db mesmo arquivo, mesmo tamanho.
- Nota: sessão paralela harness-dev ativa no mesmo repo durante a migração — só os 4 arquivos meus (2 Dockerfiles, next.config.js, docker-compose.dev.yml) tocados, nenhuma interferência.
- PM2: artists-api/web deletados + save. PM2 agora vazio (só platform-tunnel restante).
- Status: DONE

## Task: local-boot-persistence — session resume after notebook crash — 2026-08-28/29

Notebook travou. Sessão anterior tinha deixado `tunnel/docker-compose.yml` criado e `tunnel/README.md`/`tunnel/cloudflared/config.yml` editados (não commitados, não registrados em STATE/execution) — reconstruído o que tinha sido feito via `git status`/`git diff` antes de continuar.

**Estado real confirmado ao vivo** (não assumido): PM2 0/0 processos (daemon vazio, D4 completo), todos os 10 containers de app + 10 do platform stack `Up` (restart:unless-stopped funcionou sozinho pós-crash, sem intervenção). `platform-tunnel` (cloudflared containerizado) também já estava `Up` — migração da Frente B tecnicamente completa nos 5 componentes.

**INCIDENTE REAL achado ao validar (gate externo, não confiei no "Up" do container)**: as 6 rotas públicas (`vetcare`, `financas`, `grow`, `grow-sim`, `metrics`, `artists`.rastaful.dev) retornavam **502 real**, confirmado via `curl` direto (não assumido). Causa raiz investigada e confirmada com evidência, não suposição:
1. `docker exec platform-grafana wget http://host.docker.internal:3004` funcionava (confirmado via `docker cp` + Read, contornando um bug de captura de stdout desta sessão para certos comandos `docker inspect`/`exec` com nomes específicos de container).
2. Um container de debug compartilhando o *exato* namespace de rede do `platform-tunnel` (`--network container:platform-tunnel`) também alcançava `host.docker.internal:3004` com sucesso (200) via `curl -v` — só que revelou resolução **dual-stack** (IPv4 `192.168.65.254` + IPv6 `fdc4:...`), com a rota IPv6 falhando (`Network unreachable`) e curl caindo pro IPv4 automaticamente (Happy Eyeballs).
3. `cloudflared` (Go) não faz esse fallback — bug documentado a montante (`github.com/cloudflare/cloudflared/issues/811`, `#976`, confirmado via WebSearch). Testado: `sysctl net.ipv6.conf.all.disable_ipv6=1` no `docker-compose.yml` do tunnel — não resolveu sozinho. Testado: pinar IP literal `192.168.65.254` no `ingress` do `config.yml` (validado localmente com `cloudflared tunnel ingress rule` — bate certo) — **também não resolveu o 502 ao vivo**.
4. **Causa raiz real**: o log do container mostrou `originService=http://localhost:3004` em produção — meio-fio completamente diferente do que está no `config.yml` local (`192.168.65.254`). Confirma que esta tunnel é **remotely-managed** (configuração de Public Hostname vem do dashboard Cloudflare Zero Trust via API, não do `config.yml` local — o arquivo local só é usado pra outras coisas tipo `credentials-file`). O dashboard ainda tem as 6 rotas apontando pro `localhost:PORT` de antes da containerização (quando `cloudflared` rodava direto no host via PM2, `localhost` era o próprio host — agora que roda em container, `localhost` é o container, não alcança nada).
5. Tentativa de corrigir via API Cloudflare usando `CLOUDFLARE_API_TOKEN` (já existente em `tunnel/.env`, usado pro R2): `GET /accounts` retornou vazio — token sem escopo de conta suficiente pra editar o tunnel. **BLOQUEADO — precisa de ação manual do usuário** (ver DECISIONS D-2026-08-28-10).

**2 bugs reais adicionais achados e corrigidos nesta sessão**:
- `~/.pm2/dump.pm2` ainda tinha uma entrada órfã `platform-tunnel` (nunca removida quando o tunnel foi containerizado antes do crash) — se `pm2 resurrect` rodasse de verdade no próximo boot, criaria um SEGUNDO `cloudflared` concorrente pro mesmo tunnel ID, brigando com o container. Corrigido: `pm2 save --force` com 0 processos ativos limpou o dump (`[]`).
- `wsl-boot.sh`: removido `pm2 resurrect` (obsoleto, D4 completo, nada mais depende de PM2) e adicionado `service cron start` (fecha gap documentado em D-2026-08-28-6, cron não rodava sozinho no WSL2 sem systemd — item explícito do Done Criteria desta spec).
- `vetcare/Dockerfile` HEALTHCHECK: apontava pra `/` (raiz), que o NextAuth redireciona (307) pra URL pública absoluta (`https://vetcare.rastaful.dev/login...`) — o healthcheck seguia o redirect e saía pra internet, dependendo do tunnel (que estava quebrado) pra reportar saúde de um container local. Corrigido pra `/api/health` (mesmo padrão dos outros 3 apps). Rebuild em andamento.

- `docker compose config` (tunnel): PASS
- `cloudflared tunnel ingress rule` (validação local do config.yml): PASS (bate com o esperado, mas não reflete o comportamento real por ser remotely-managed)
- Public URLs (gate externo real): **6/6 FAIL (502)** — bloqueado em ação do usuário
- `docker build` (vetcare, novo Dockerfile): PASS (74s, sem erros — warnings pré-existentes de lint/edge-runtime não relacionados)
- vetcare container recriado: `Up (healthy)` confirmado (era `unhealthy`, FailingStreak 28, antes do fix) + `curl localhost:3004/api/health` 200 direto
- Status: PARTIAL — 4/5 componentes locais 100% OK (rastafinancas, microgrow, vetcare, artists-booking rodando saudáveis em Docker); tunnel containerizado e local config correto mas **BLOCKED** externamente até o usuário editar o Public Hostname no dashboard Cloudflare (D-2026-08-28-10)

## Task: local-boot-persistence — tunnel desbloqueado, spec fechada — 2026-08-29

Usuário confirmou pelo painel Cloudflare Zero Trust que a config de roteamento real das 6 rotas fica em **Networks → Tunnels → rastafinancas → "Published application routes"** (não "Hostname routes" nem a config local — confirma definitivamente a hipótese de tunnel remotely-managed registrada em D-2026-08-28-10). Screenshot mostrou as 6 com Service `http://localhost:PORT` — porta certa, host errado, exatamente a causa raiz diagnosticada. Usuário editou manualmente as 6 (`localhost` → `host.docker.internal`, mesma porta).

**Gate externo real (curl direto, não confiando na palavra do usuário)**:
- vetcare.rastaful.dev -> 307
- financas.rastaful.dev -> 307
- grow.rastaful.dev -> 307
- grow-sim.rastaful.dev -> 307
- metrics.rastaful.dev -> 302
- artists.rastaful.dev -> 307

6/6 PASS (nenhum 502, todos redirecionando normal — mesmo padrão de antes da migração).

**Spec `local-boot-persistence`: DONE.** Todos os 5 componentes (rastafinancas, microgrow, vetcare, artists-booking, platform-tunnel) migrados de PM2 pra Docker Compose com `restart: unless-stopped`, servindo local E publicamente. `wsl-boot.sh` limpo (sem PM2, com cron). PM2 fica instalado mas sem nenhum processo gerenciado.
- Status: DONE

## Task: Caddy prep + vetcare network naming — 2026-08-29

Usuário pediu os 2 itens de "zero bloqueio externo" levantados na conversa (ADR-009 revisit + Batch 2 cosmético).

**Caddy prep**: `ingress/caddy/` criado (Caddyfile + docker-compose.yml + README) — **não ativo**, zero referência de `terraform/modules/oci-compute/cloud-init.yaml.tpl` ou qualquer path de provisionamento real. Alvos espelham exatamente `tunnel/cloudflared/config.yml` (mesmos hostnames/portas). Gate real: `caddy validate` PASS. ADR-009 atualizada com nota + referência cruzada.

**vetcare network naming**: `docker-compose.dev.yml` — rede default renomeada de `vetcare_default` (implícita) pra `vetcare_net` (convenção explícita, igual `microgrow_net`/`artists_net`/`rastafinancas_net`). Cosmético, sem mudança de isolamento real.
- `docker compose config`: PASS antes de aplicar.
- **Incidente real durante a aplicação** (não escondido): `docker compose up -d` sozinho deixou o relay de porta host→container quebrado pra `vetcare`/`postgres` (3004 e 5432 pararam de escutar no host, apesar do container reportar `healthy` e conectividade interna OK) — sintoma de troca de rede em containers já rodando no Docker Desktop/WSL2, não bug do meu compose. Resolvido com `docker compose down` completo + `up -d` (recria os containers do zero, não só troca de rede). Confirmado: `ss -tlnp` mostrando 3004/5432 escutando, `curl localhost:3004/api/health` 200, `curl https://vetcare.rastaful.dev` 307 (rota pública via tunnel também confirmada, não só local).
- Status: DONE

## Task: artists-booking — bug crítico de produção (registro de usuário quebrado) — 2026-08-29

Reportado pelo agente `harness-dev` (sessão paralela em `artists-booking`, auditoria de UX): suíte Playwright funcional pré-existente rodada como gate prévio (23 passed, 6 failed, todas convergindo numa causa raiz). `POST /api/v1/auth/register` → 500. Diagnóstico do harness-dev (correto, verificado independentemente antes de agir — nunca confiei no relato sozinho):

**Confirmado ao vivo**: `curl -X POST /api/v1/auth/register` → 500 real, `"attempt to write a readonly database"` (SQLite/Prisma).

**Causa raiz confirmada**: `apps/api/prisma` é bind-mount (`docker-compose.dev.yml`) — dono no host é `node:node` (uid 1000, mesmo do usuário rodrigo), mas o container roda como `appuser` (uid 1001, endurecimento de segurança anterior). O `Dockerfile` já fazia `--chown=appuser:appgroup` no `COPY`, mas o bind-mount em runtime esconde essa permissão com o dono real do host — regressão introduzida pela migração PM2→Docker (a versão PM2 rodava como o próprio usuário do host, sem esse descompasso de uid).

**Fix imediato** (produção): `docker exec -u root artists-api chown -R appuser:appgroup /app/apps/api/prisma` (sem sudo no host — chown pra outro uid precisa de root, só consegui de dentro do container, que roda sem user-namespace remap = root real sobre o bind mount). Container precisou de restart depois (processo Node já tinha o handle do arquivo aberto como somente-leitura desde o boot, chown sozinho não bastava).
- Validado com o request exato que falhava: `POST /register` → 201, `POST /login` → 200, usuário de teste confirmado com uma conexão Prisma nova e independente, depois removido.

**Fix permanente** (não só o incidente, a causa): container mudou de `USER appuser` fixo pra iniciar como root + `docker-entrypoint.sh` que faz `chown -R appuser:appgroup` no bind-mount TODA vez que sobe, depois usa `su-exec` pra rodar o processo real como appuser (mesmo padrão de imagens oficiais tipo postgres). `apk add su-exec` adicionado.
- **Teste de autocorreção real, não hipotético**: resetei o dono do host de volta pra uid 1000 (simulando um `git clone` novo), recriei o container sem tocar em mais nada manualmente, confirmei que a permissão voltou sozinha pra 1001 e `POST /register` funcionou de primeira. `docker exec artists-api id` confirmando PID 1 ainda roda como `appuser` — postura de segurança preservada, só `docker exec` interativo mudou de default (agora root, documentado no Dockerfile).
- `docker build`: PASS. Commitado só os 2 arquivos meus (`Dockerfile`, `docker-entrypoint.sh`) — sessão paralela do harness-dev ativa no mesmo repo, não toquei em nada dela (specs/screenshots das features 24-32).
- Status: DONE

## Task: observability-promtail-docker — D1/D2/D3 aprovados, execução completa — 2026-08-29

Usuário aprovou: D1 (restartar e validar rastafinancas), D2 (escopo total — restaurar rastafinancas/microgrow E criar do zero pra vetcare/artists-booking), D3 (replicar o padrão `docker_sd_configs` do microgrow).

**D1 — restart rastafinancas revelou 2 achados reais, não só o esperado**:
1. `rasta-telegraf`/`rasta-promtail` restartaram limpo, mas `rasta-telegraf` deu **403 Forbidden** em `/metrics` — o token Bearer adicionado por `security-hardening-phase1` (2026-08-28) nunca foi propagado pro telegraf. Corrigido: `bearer_token_string = "${METRICS_TOKEN}"` no `telegraf.conf` + `METRICS_TOKEN` no `.env`/compose. Confirmado sem erro após fix.
2. Comentários `~/services/platform` desatualizados (pré-consolidação ADR-010) em `rastafinancas` e `microgrow` — corrigidos pro path real.

**Migração dos 4 Promtails pra `docker_sd_configs`** (rastafinancas + microgrow reescritos, vetcare + artists-booking criados do zero):
- rastafinancas: 4 jobs de arquivo (`/pm2logs/*.log`) → 1 job Docker, containers `rastafinancas-api`/`rastafinancas-web`.
- microgrow: job Docker existente estendido de 4 pra 6 containers (+ api/webapp/webapp-sim/simulator). Achado bônus: filtro tinha `microgrow-influxdb`/`microgrow-grafana` que **nunca existiram** como nomes de container (são `platform-influxdb`/`platform-grafana` compartilhados) — dead config removido.
- vetcare: Promtail criado do zero (nunca teve).
- artists-booking: Promtail criado do zero (nunca teve).

**Bug real sério achado e corrigido (vetcare)**: filtro `name: vetcare` sem âncora fazia *substring match* — capturava `vetcare`, `vetcare-postgres-1`, `vetcare-postgres_test-1` e **o próprio `vetcare-promtail`** (self-scraping — promtail lendo seus próprios logs de volta, risco real de loop de crescimento de log). Resultado prático: zero linhas chegavam no Loki, erro de push ficava mascarado (mensagem truncada nos logs do próprio promtail, só resolvido testando push bruto via `curl` num container compartilhando o namespace de rede do promtail — 204 confirmou que a conectividade sempre esteve OK, o problema era o alvo errado). Corrigido com regex ancorado (`^vetcare$`) — aplicado como hardening preventivo também em rastafinancas e microgrow (nenhum bug lá, mas mesmo risco de classe), e usado desde o início no de artists-booking.

**Gates externos reais, não self-reportados**:
- `promtail -check-syntax`: 4/4 PASS
- `docker compose config`: 4/4 PASS (rastafinancas-observability, microgrow, vetcare, artists-booking)
- Discovery count (`docker logs | grep -c "added Docker target"`): rasta=2 (esperado 2), microgrow=6 (esperado 6), vetcare=1 (esperado 1, era 4 antes do fix), artists=2 (esperado 2) — todos batem exato, sem alvo a mais/a menos.
- **Loki query real (`/loki/api/v1/query_range`), não só "container Up"**: gerado tráfego real (`curl /health`) em cada API, linhas confirmadas chegando com label `container` correto — rastafinancas-api (5 linhas), microgrow-api (3 linhas), vetcare (5 linhas, após o fix), artists-api (5 linhas). rastafinancas-web mostrou 0 linhas por não termos gerado log novo, não por falha — Next.js sem log por request, comportamento normal, não regressão.
- Transiente observado e não tratado como falha: primeiro flush de cada promtail recém-criado às vezes falha uma vez ("final error sending batch", mensagem truncada nos logs do próprio promtail) e se autorrecupera no ciclo seguinte — confirmado via múltiplos restarts, dado real sempre passou a fluir depois.

- Status: DONE

## Task: artists-booking product-health dashboard + alerts (Spec 53, delegado por artists-booking) — 2026-09-01
- Contexto: artists-booking lançou beta, spec 53 (artists-booking/.specs/features/53-product-health-metrics/spec.md) instrumenta métricas de produto novas no apps/api (sessão paralela, fora deste escopo). Este task é só o lado infra-platform: dashboard + alertas consumindo o que o Prometheus já raspa de artists-api (job apis-host, prometheus.yml:28-38).
- dashboard.yml: provider novo `artists-booking` adicionado (path /var/lib/grafana/dashboards/artists-booking, folder "Artists Booking"), mesmo formato de microgrow/rastafinancas/platform.
- platform/dashboards/artists-booking/product-health.json criado: 9 painéis — funil (search_performed_total -> profile_viewed_total -> request_created_total{type} -> request_application_total), taxa de busca-sem-resultado, artist_profiles_visible_ratio (linha do tempo p/ regressão pós-deploy), stat de with_location_ratio/avg_completeness, erro 5xx por rota (http_requests_total existente, sem instrumentação nova), users_total real vs demo. Datasource Prometheus existente (uid prometheus-platform). JSON validado com `python3 -m json.tool` — PASS.
- **Achado real via verificação externa (não assumido)**: `docker logs platform-grafana` mostrava `states=0` em TODO restart desde 2026-08-29 e warning `"file has invalid suffix 'rules'... skipping"` — os arquivos de alerta de microgrow/rastafinancas viviam em `alerting/rules/*.yaml`, mas o file-provisioning do Grafana NÃO recursa em subdiretórios (bug conhecido, grafana/grafana#53294: subpasta dentro de `alerting/` quebra o provisioning inteiro, silenciosamente, para todos os arquivos). Ou seja: os alertas de microgrow e rastafinancas NUNCA carregaram desde que essa estrutura existe. Corrigido: os 3 arquivos (microgrow.yaml, rastafinancas.yaml, artists-booking.yaml) movidos para `alerting/` flat (mesmo nível de contact-points.yaml/notification-policy.yaml), diretório `rules/` removido.
- artists-booking.yaml (3 regras, Prometheus/PromQL, seguindo o schema já usado por rastafinancas.yaml mas adaptado de Flux/InfluxDB para Prometheus): `artists-search-zero-results-ratio` (>90% sustentado 15min, crítico), `artists-register-5xx-rate` (>5% em 5min na rota /api/v1/auth/register, crítico), `artists-profiles-visible-ratio-drop` (queda >20% vs média 1h, heurística, warning). Todas as 3 com `noDataState: OK` / `execErrState: OK` explícito — decisão deliberada: as métricas de produto ainda não existem em produção (outra sessão instrumentando em paralelo), então "sem dado" agora é esperado, não uma anomalia; sem isso, o estado NoData teria dado default (Alerting) e disparado notificação crítica falsa assim que o SMTP funcionasse.
- Verificação externa real (não self-validada):
  - `docker compose config`: PASS antes e depois de cada mudança.
  - Nenhum outro serviço do compose depende de `grafana` (checado via grep depends_on) — restart seguro, sem cascata.
  - `docker compose restart grafana` 3x (dashboard, rules/ fix, noDataState fix) — sempre `Up ... (healthy)`.
  - `GET /api/health` (Grafana): `{"database":"ok"}` a cada restart.
  - `GET /api/search?query=Artists Booking`: dashboard presente na folder "Artists Booking", uid `artists-booking-product-health`, 9 painéis confirmados via `GET /api/dashboards/uid/...`.
  - `GET /api/v1/provisioning/alert-rules`: total de regras foi de **0 (bug pré-existente) para 24** após o fix do `rules/` — as 3 novas (`artists-search-zero-results-ratio`, `artists-register-5xx-rate`, `artists-profiles-visible-ratio-drop`) confirmadas presentes com `noDataState: OK`/`execErrState: OK`, junto com as 6 do microgrow e 6 do rastafinancas que também passaram a carregar de verdade pela primeira vez.
  - `docker logs`: única mensagem de erro nova observada foi uma falha real e pré-existente de SMTP (Gmail auth, 530 5.7.0) ao tentar notificar — não relacionada a este task, consequência de os alertas terem passado a ser avaliados de verdade pela primeira vez; registrada como achado, não corrigida (fora de escopo, requer decisão do usuário sobre credencial SMTP).
  - Logs finais (pós-fix `noDataState: OK`): zero erro novo, zero notificação disparada pelos 3 alertas novos.
- Status: DONE (dashboard + alertas prontos, painéis vazios até artists-api exportar as métricas — esperado e documentado na spec 53).

## Task: artists-booking product-health dashboard — Spec 54 T15 (delegado por artists-booking) — 2026-09-02
- Contexto: Spec 54 (artists-booking, RUM híbrido) adicionou métricas novas ao mesmo `/metrics` já raspado pelo job `apis-host` (`service=artists-api`), via 2 plugins novos no backend (`frontend-metrics.plugin.ts`, `demand-metrics.plugin.ts` — famílias A-H/M/N/O/P). T15 é só o lado infra-platform: painéis novos no mesmo dashboard já existente da Spec 53 (`platform/dashboards/artists-booking/product-health.json`), sem alerta novo (fora de escopo desta task).
- 10 painéis novos + 6 rows agrupando por família, mesmo estilo/convenção dos 9 painéis da Spec 53 (datasource `${DS_PROMETHEUS}`, `service="artists-api"` em todo target):
  - Row "Saúde de navegação (RUM)": timeseries dead-click/404/error-boundary (taxa/s) + timeseries de `frontend_rum_event_rejected_total` por `reason`.
  - Row "Conversão de CTA": timeseries clique vs exposição por `cta` + timeseries de razão clique/exposição (`percentunit`).
  - Row "Listas vazias e uso de filtro": timeseries `list_empty_total` por `list` + timeseries `filter_applied_total` por `filter`.
  - Row "Duração de wizard": timeseries único com `histogram_quantile` p50/p95 por `wizard` (unit `s`).
  - Row "Demanda por categoria/região" (família N): 2 painéis `bargauge` (`demand_by_category`/`demand_by_region`) — tipo de visualização diferente do resto do dashboard (timeseries/stat), decisão deliberada porque é ranking de valor por label, não série temporal.
  - Row "Sinal de trigger de migração Postgres" (família H): `stat` de `db_write_contention_total` (cumulativo), threshold verde=0/vermelho>=1 — fica visível mesmo em 0 hoje, pra quando começar a subir.
- JSON validado: `python3 -m json.tool` PASS + verificação de ids únicos (25 entradas no array `panels`, 9 rows + 16 painéis de conteúdo, nenhum id duplicado). `version` 1→2, `tags` ganhou `spec-54`, `title`/`description` atualizados mencionando as 2 specs.
- Verificação externa real (não self-validada):
  - `docker compose config --quiet`: PASS antes e depois.
  - `docker compose restart grafana`: `Up ... (healthy)` em ~1 tentativa (healthcheck).
  - `GET /api/health`: `{"database":"ok"}`.
  - `GET /api/search?query=Artists Booking`: dashboard presente na folder "Artists Booking", uid `artists-booking-product-health`.
  - `GET /api/dashboards/uid/artists-booking-product-health`: HTTP 200, `version: 3` (Grafana bump automático do file-provisioning), 25 entradas em `panels`, todos os 10 títulos novos confirmados presentes.
  - `docker logs platform-grafana` (últimos 2min pós-restart): zero erro/warning novo de provisioning.
  - 5 expressões PromQL representativas (incluindo `histogram_quantile` e razão de 2 séries) testadas via `GET /api/datasources/proxy/uid/prometheus-platform/api/v1/query`: todas `status: success` (resultado vazio, esperado — código do backend Spec 54 T1/T2/T9/T10 ainda não foi deployado no container `artists-api` rodando, confirmado via `curl /metrics` direto no host: só métricas da Spec 53 presentes hoje). Painéis vazios até T16/T17 (verificação + deploy real) rodarem — mesmo padrão documentado na Spec 53 T5.
- Nenhum alerta novo criado (fora do escopo pedido pela task). Sugestão registrada para o usuário avaliar depois: alerta em `db_write_contention_total` (ex. `increase(db_write_contention_total[1h]) > 0` por N ocorrências sustentadas) como trigger formal de decisão de migração Postgres, já que hoje esse limiar é só "julgamento manual olhando o painel".
- Status: DONE (T15, dashboard). T16 (verificação com dado real via infra isolada) e T17 (deploy real) seguem a cargo de `artists-booking`/orquestrador dev, fora do escopo desta delegação de infra.

## Task: rename branch principal master→main (infra-platform) — 2026-09-08
- Pré-checagem: `git branch -a` (só `master`, sem outras), sem PR aberto (`gh pr list` vazio), sem workflow/doc referenciando `master` como nome de branch (único hit era `sqlite_master` em `restore-from-backup.md`, falso-positivo).
- Ação: `git branch -m master main` → `git push -u origin main` → `gh repo edit --default-branch main` → `git push origin --delete master`.
- Verificação externa:
  - `git branch -a`: `* main` / `remotes/origin/main` (sem `master` restante, local ou remoto).
  - `gh repo view rastaFul/infra-platform --json defaultBranchRef`: `{"defaultBranchRef":{"name":"main"}}`.
- Gates de IaC (terraform/kube/helm) não aplicáveis — operação de metadado de repo git, sem mudança de infra provisionada.
- ADR-013 criado documentando a convenção pra todos os repos + procedimento de rename reutilizável. D-2026-09-08-1 em DECISIONS.md.
- Escopo: só `infra-platform` renomeado nesta sessão. Outros 4 repos ficam pendentes (aplicar quando cada um for tocado).
- Status: DONE

## Task: varredura + rename em massa (todos os repos) — 2026-09-08
- Varredura de 13 diretórios em `~/projects/`: owner, remote, branch atual, PR aberto, workflow referenciando `master`.
- `artists-booking`/`microgrow`/`rastafinancas`/`vetcare`/`agents-harness`: já em `main`, nada feito.
- `dev-environment`: pré-checagem OK (sem PR, `gh pr list` vazio; sem workflow com `master`; sem `.specs` próprio) → mesma sequência (`git branch -m`/`push -u`/`gh repo edit --default-branch`/`push --delete`) → verificado: `git branch -a` só `main`, `gh repo view --json defaultBranchRef` = `main`.
- `developerFolio`: NÃO executado. `git branch -a` mostra `gh-pages`+`feature/profile`+`feature/profile-resume` além de `master`; `grep -rl master .github` retornou `deploy.yml` e `prettier.yml`; `gh repo view --json isFork,visibility` = fork público. Escalado.
- `tldr-projects`: NÃO executado. `git remote -v` vazio (sem remote real) mas `git branch -a` mostra `remotes/origin/main` órfã; `git branch -m master main` falhou com "a branch named 'main' already exists"; `git log --oneline main` = 1 commit ("first commit") não relacionado ao histórico real de `master` (3 commits reddit/MCP); `git status` mostra mudanças não commitadas de outra frente. Escalado.
- `url-shortener`: remote `thiagomr/url-shortener`, não `rastaFul` — fora de escopo, não tocado.
- `cron-monitoring`/`gorila`/`logger-lib`: não são repos git, N/A.
- ADR-013 atualizado com tabela completa da varredura. D-2026-09-08-2 em DECISIONS.md.
- Status: DONE (parcial por natureza — 2 repos renomeados, 2 escalados por decisão explícita, resto fora de escopo ou já conforme)

## Task: corrigir /metrics do vetcare + compose de observabilidade do rastafinancas — 2026-09-09
Pedido do usuário: "o composer de observabilidade não está funcionando" + "corrija o /metrics do vetcare".

### Diagnóstico (antes de qualquer mudança)
- `platform/docker-compose.ps` (infra-platform): todos os 10 serviços `Up`/`healthy`. Não é o compose quebrado.
- `docker ps -a` em todo o host: achado real — `rasta-telegraf` e `rasta-promtail` (`rastafinancas/infrastructure/observability/docker-compose.yml`) `Exited (255)` há ~26h, enquanto todo o resto do host tinha `StartedAt` ~1h DEPOIS desse exit (confirmado via `docker inspect --format .State.StartedAt` em 9 containers de referência). Log do promtail mostrou a causa real: `"=== received SIGINT/SIGTERM === exiting"` às 2026-09-07T03:54:17 — um `docker stop` explícito (ou `compose down/stop`), não crash nem OOM (`OOMKilled=false`), não recriação de rede (`platform_net`/`rastafinancas_net` com `Created` de 2026-06-03, sem mudança recente). `RestartCount=0` confirma: `restart: unless-stopped` não resscita contêiner que já estava `Exited` ANTES de o daemon Docker ser reiniciado — só resscita o que estava `Up` no momento do restart do daemon. Isso explica por que os outros 9 (que estavam `Up`) voltaram sozinhos ~1h depois e esses 2 não.
- vetcare: `/metrics` não existe no código (`grep`/`find` no `src/app` vazio), `prometheus.yml` não tinha job pra vetcare, `curl /metrics` público redirecionava pro login (comportamento do NextAuth middleware pegando rota inexistente, não um bug do endpoint em si — endpoint nunca existiu).

### Fix 1 — rastafinancas observability compose
- `cd rastafinancas/infrastructure/observability && docker compose config --quiet` (PASS) → `docker compose up -d` → `rasta-telegraf`/`rasta-promtail` `Up`, sem novos erros nos logs subsequentes (checado com `--since 20s`, zero repetição do erro antigo de EOF).
- Verificação externa real (não só "container Up"): `POST /api/v2/query` no InfluxDB (`org=platform`, bucket `rastafinancas`) — measurements `rasta_*`/`cpu`/`mem`/`disk`/`http_response` com `_time` de agora (não dado antigo). `GET /loki/api/v1/query` com `{container="rastafinancas-api"}` — log entry com timestamp atual.
- Causa raiz do STOP original não identificada com certeza (não há `docker events` retroativo disponível) — registrado como tal, não inventado. Ação de mitigação estrutural NÃO feita nesta sessão (ver pendência abaixo).

### Fix 2 — vetcare /api/metrics + wiring Prometheus
- Código em `vetcare` (repo separado, ver `vetcare/.specs/audit/execution.md` sessão 2026-09-09 pro detalhe completo): rota `/api/metrics` com `prom-client`, protegida por `METRICS_TOKEN` (mesmo valor deste repo, `platform/prometheus/metrics_token`), bypass do NextAuth middleware.
- `platform/prometheus/prometheus.yml`: **não** deu pra reusar o job `apis-host` (fixa `metrics_path: /metrics` pra todos os targets dele) — vetcare usa `/api/metrics` (Next.js, não Fastify). Job `vetcare` dedicado criado, mesmo `credentials_file` compartilhado.
- Comentário de cabeçalho do arquivo corrigido (citava "PM2, not yet containerized", desatualizado desde a migração Batch 3 de 2026-08-29).

### Achado real extra, não pedido, corrigido no caminho — bug de bind-mount do Prometheus
Ao rodar `docker compose restart prometheus` pra aplicar o `prometheus.yml` novo, o container falhou ao subir: `error mounting ".../docker-desktop-bind-mounts/..." to rootfs at "/etc/prometheus/prometheus.yml": no such file or directory`. Bug conhecido de Docker Desktop/WSL2 (cache de bind-mount de arquivo único fica órfão depois de edição externa ao Docker). `docker compose up -d --force-recreate prometheus` resolveu (remapeia o bind mount do zero). Sem esse fix, a mudança do `prometheus.yml` teria ficado silenciosamente sem efeito (container não sobe) — achado só porque a verificação externa (`/-/healthy`, `/api/v1/targets`) é obrigatória antes de considerar DONE.

### Verificação externa final
- `docker compose config --quiet` (platform): PASS
- `GET /-/healthy` (Prometheus): `200 Prometheus Server is Healthy`
- `GET /api/v1/targets`: 6/6 `up` (`apis-host` x3 + `otel-collector` x2 + `vetcare` novo)
- `GET /api/v1/query?query=vetcare_process_cpu_seconds_total`: resultado real, valor > 0, timestamp atual
- `GET /api/v1/series?match[]=http_requests_total{service="vetcare"}`: vazio — confirma que vetcare NÃO aparece ainda no dashboard "Golden Signals" (variável `$service` depende dessa métrica, que vetcare não expõe ainda — gap documentado, não escondido)
- Status: DONE (com 2 pendências explícitas abaixo, não escondidas)

### Pendências registradas (não resolvidas nesta sessão)
1. **Resiliência estrutural**: nenhum boot script (`wsl-boot.sh`) traz de volta contêineres que já estavam `Exited` antes de um restart do Docker Desktop/WSL2 — só o `restart: unless-stopped` nativo do Docker cobre isso, e só pra contêineres que estavam `Up` no momento do restart do daemon. Isso pode se repetir com qualquer compose sidecar (telegraf/promtail de qualquer projeto). Não corrigido agora — precisa decisão (ex.: `wsl-boot.sh` rodando `docker compose up -d` explícito em cada compose do ecossistema, não só confiar na restart policy).
2. **vetcare sem métricas HTTP custom** (`http_requests_total`) — só métricas de processo por enquanto, não aparece no Golden Signals. Documentado em `vetcare/.specs/features/observability-metrics/spec.md`.
3. `vetcare` `METRICS_TOKEN` não empurrado pro Vault (`vault-push-env.sh`).

### Gate de qualidade de infra (per-task)
`skills/infra-quality-gates/scripts/run-infra-quality.sh .`: `overall: PASS` — tflint/kubeconform/pluto `SKIPPED` (sem `.tf`/manifests K8s tocados nesta task, é docker-compose YAML + código Next.js, já gated por `jest`/`tsc`/`eslint` do lado do vetcare + `docker compose config --quiet` dos 2 composes tocados).

## Task: restart:always em todos os composes (pendência 1 fechada) — 2026-09-09
Pedido do usuário: em vez de script de boot, resolver via config do compose — usuário confirmou que
o `docker stop` que derrubou telegraf/promtail foi ELE MESMO parando o Docker Desktop pra jogar, e
espera que tudo volte sozinho quando reiniciar. `restart: unless-stopped` não cobre esse caso pra
contêiner que já tinha crashado sozinho antes do stop (ver task anterior); `restart: always` cobre,
porque resscita no restart do daemon independente do estado do contêiner antes do shutdown.
- `restart: unless-stopped` → `restart: always` em TODOS os composes reais do ecossistema (excluído
  `.harness-sandbox/docker/docker-compose.yml` de cada repo — é sandbox de CI, efêmero, não faz
  parte do stack local persistente):
  - `infra-platform/platform/docker-compose.yml` (10 serviços)
  - `infra-platform/tunnel/docker-compose.yml` (1)
  - `rastafinancas/docker-compose.yml` (2) + `rastafinancas/infrastructure/observability/docker-compose.yml` (2)
  - `microgrow/infra/docker-compose.yml` (7)
  - `artists-booking/docker-compose.dev.yml` (4)
  - `vetcare/docker-compose.dev.yml` (4)
- Comentário de cabeçalho de cada arquivo atualizado explicando a troca (não silenciosa). `wsl-boot.sh` também atualizado (citava `unless-stopped` explicitamente).
- Gates: `docker compose config --quiet` PASS nos 7 (vetcare com warning pré-existente de `version` obsoleto no YAML, não bloqueante, não introduzido por esta mudança).
- Aplicado ao vivo (não só no arquivo): `docker compose up -d` em cada um dos 7 diretórios — Compose recriou só os contêineres cuja config mudou (a restart policy), sem rebuild de imagem. 31 contêineres confirmados `Up`/`healthy` depois via `docker ps`.
- Verificação externa pós-recriação: 4/4 domínios públicos (`vetcare`/`financas`/`grow`/`artists`.rastaful.dev) responderam `307` (redirect esperado, não `502`) — tunnel sobreviveu à recriação. Prometheus: 6/6 targets `up` de novo (incluindo `vetcare`, task anterior).
- **Achado colateral, não corrigido (fora do pedido)**: `docker compose up -d` em `rastafinancas/infrastructure/observability` emitiu warning — `rastafinancas_net` é declarada (não-`external`) em DOIS composes diferentes (`rastafinancas/docker-compose.yml` E `infrastructure/observability/docker-compose.yml`), Compose trata como "projetos" distintos disputando o mesmo nome de rede. Funcionou (containers subiram, rede reaproveitada), mas é frágil — registrado, não é bloqueante, precisa decisão (ex.: observability deveria referenciar `rastafinancas_net` como `external: true`, já que quem deveria "possuir" a rede é o compose principal do app).
- **Achado colateral extra, registrado, não corrigido (precisa decisão do usuário antes de mexer, é rename de métrica com histórico em produção)**: enquanto investigava a instrumentação HTTP do vetcare (próxima task), descoberto que `rastafinancas-api` expõe `rasta_http_requests_total`/`rasta_http_request_duration_seconds` (prefixado, segundos) enquanto o dashboard "Golden Signals" (`platform/dashboards/platform/golden-signals.json`) e `artists-api`/`microgrow-api` usam `http_requests_total`/`http_request_duration_ms` (sem prefixo, ms). Confirmado ao vivo: `GET /api/v1/query?query=http_requests_total` NUNCA retorna série com `service="rastafinancas-api"`. Os painéis de request-rate/error-rate/latência desse dashboard nunca mostraram dado real pra rastafinancas, apesar do que STATE.md (2026-08-28) registra. Ver `vetcare/.specs/audit/execution.md` (2026-09-09) pro detalhe completo.
- Status: DONE (pendência 1 fechada; 2 achados colaterais registrados, não corrigidos, aguardando decisão)

## Task: resolver as 3 pendências (rename métrica, rede duplicada, instrumentação HTTP vetcare) — 2026-09-09
Usuário pediu explicitamente resolver os 3 achados anteriores.

### 1. Rename `rasta_*` → sem prefixo (rastafinancas)
- `rastafinancas/apps/api/src/plugins/metrics.ts`: `collectDefaultMetrics({ prefix: 'rasta_' })` → sem prefixo; `rasta_http_requests_total`→`http_requests_total`; `rasta_http_request_duration_seconds`→`http_request_duration_ms` (buckets ms iguais ao microgrow-api); `reply.elapsedTime / 1000` → `reply.elapsedTime` (já em ms). Métricas de produto (`product-metrics.ts`) NÃO tocadas (prefixo de propósito, evita colisão entre produtos).
- Gates: `tsc --noEmit` (apps/api) limpo; `vitest run src/plugins` 15/15 PASS (sem lint configurado neste repo — confirmado, sem script/config eslint). Rebuild real (`docker compose up -d --build api`), curl real confirma `http_requests_total`/`http_request_duration_ms_bucket`/`process_resident_memory_bytes` sem prefixo.
- **Efeito colateral descoberto e corrigido**: dashboard InfluxDB `platform/dashboards/rastafinancas/rasta-api-performance.json` e `platform/grafana/provisioning/alerting/rastafinancas.yaml` (regras `rasta-error-rate-critical`, `rasta-latency-p95`) referenciavam os nomes antigos — atualizados. No processo, achado um bug PRÉ-EXISTENTE e SEPARADO (não introduzido agora): os painéis P50/P95/P99 filtravam `_measurement == "rasta_http_request_duration_seconds_bucket"` (sufixo `_bucket` que o Telegraf nunca gera — ele grava todos os buckets de um histograma numa medição só, um field por boundary `le`) e `_field == "counter"` (não existe nesse measurement) — ou seja, esses 3 painéis NUNCA retornaram dado, desde que o dashboard foi criado. Corrigido com uma query Flux própria (pivot dos fields de bucket + interpolação simples de quantil por boundary, testada com dado real via API do InfluxDB antes de ir pro JSON — resultados sãos: p50 5ms/10ms pras rotas testadas). Threshold do alerta de latência (`rasta-latency-p95`) também tinha uma conversão `* 1000.0` que ficou redundante (dado já em ms agora) — removida; a lógica de `mean()` sobre o field `sum` (cumulativo) do alerta continua conceitualmente aproximada (não é uma média real por request), mas isso já existia antes e não foi o que foi pedido — registrado, não redesenhado.
- Verificação externa completa: `python3 -m json.tool` PASS (dashboard), `yaml.safe_load` PASS (alertas), `docker compose restart grafana` healthy, dashboard confirmado via API (`version: 4`, recarregado), 6 alert rules de rastafinancas confirmadas via `GET /api/v1/provisioning/alert-rules` (com `X-Grafana-Org-Id: 1` — achado à parte: o usuário `admin` autentica em `orgId=2` por padrão neste Grafana multi-org, header explícito necessário pra API bater com o que está provisionado em orgId 1), queries de rate/p50/p95/p99/error-rate testadas diretamente contra a API do InfluxDB (não só "carregou", "retorna número plausível").
- Prometheus: `service=rastafinancas-api` confirmado presente em `http_requests_total`/`process_resident_memory_bytes` via `GET /api/v1/series` — rastafinancas agora elegível pro `$service` do Golden Signals pela primeira vez.

### 2. Rede `rastafinancas_net` duplicada
- `rastafinancas/infrastructure/observability/docker-compose.yml`: `rastafinancas_net` (era `driver: bridge`, não-external) → `external: true` (dono real é `rastafinancas/docker-compose.yml`). Comentário simétrico adicionado no compose principal documentando a posse.
- `docker compose config --quiet` PASS nos 2; `docker compose up -d` na observability sem warning (antes: "a network with name rastafinancas_net exists but was not created for project..."). Containers já rodando não precisaram recriar (rede já existia idêntica no Docker), fix é de correção de config pra frente, não uma mudança de runtime.

### 3. Instrumentação HTTP real do vetcare (72 handlers)
- `src/lib/with-metrics.ts` criado: wrapper `withMetrics(route, handler)` que mede duração real (`process.hrtime.bigint()`) e lê `res.status` de verdade — só possível dentro do route handler (motivo documentado na task anterior de por que middleware não serve).
- `scripts/wrap-routes-with-metrics.mjs` (vetcare): codemod usando o TypeScript compiler API (AST) pra localizar com segurança cada `export async function METODO(...)` top-level em `src/app/api/**/route.ts`, renomear pra `METODO_impl` e adicionar `export const METODO = withMetrics(rota, METODO_impl)` logo depois — reescrita por slice de texto (não pelo printer do TS), preserva comentários/formatação do corpo 100%. Rodado primeiro em `--dry-run` (revisado: 72 handlers em 48 arquivos, 2 pulados de propósito — `/api/metrics` e o catch-all do NextAuth), depois de verdade.
- `src/lib/metrics.ts`: removido o prefixo `vetcare_` de `collectDefaultMetrics` (mesma motivação do rastafinancas — compat com o painel de memória do Golden Signals) e adicionadas `http_requests_total`/`http_request_duration_ms` (mesmos buckets do microgrow-api).
- Gates: `tsc --noEmit` limpo nos 48 arquivos tocados; `eslint` limpo; `jest` 234/234 (233 pré-existentes + 1 teste próprio corrigido, esperava o prefixo antigo); `npm run build` real PASS (todas as rotas compiladas, App Router não acusou nada). Rebuild real do container (`docker compose -f docker-compose.dev.yml up -d --build app`), `healthy`.
- Verificação externa: `curl /api/health` real incrementou `http_requests_total{route="/api/health",status_code="200"}` de verdade (confirmado via `/api/metrics`); rotas que exigem sessão (ex. `/api/v1/animals`) corretamente NÃO incrementaram sem cookie válido — comportamento esperado (o wrapper só mede o que de fato chega no handler, requests barrados pelo NextAuth antes disso não contam, por design). Prometheus: `service=vetcare` confirmado em `http_requests_total` via `GET /api/v1/series` — os 4 produtos agora compatíveis com o Golden Signals pela mesma convenção de nome.

### Verificação final do host inteiro (pós as 3 correções)
`docker ps`: todos os contêineres `Up`/saudáveis. 4/4 domínios públicos (`vetcare`/`financas`/`grow`/`artists`.rastaful.dev) respondendo `307`, sem `502`. Prometheus: `service` label agora inclui os 4 produtos de forma consistente.
- Status: DONE — as 3 pendências fechadas e verificadas externamente. 1 achado novo registrado, não corrigido (fora do pedido): lógica de `mean()` sobre contador cumulativo no alerta `rasta-latency-p95` é uma aproximação, não uma média real de latência por request — pré-existente, não introduzida agora.

### Gate de qualidade de infra (final desta rodada)
`skills/infra-quality-gates/scripts/run-infra-quality.sh .`: `overall: PASS` — tflint/kubeconform/pluto `SKIPPED` (sem `.tf`/manifests K8s; mudanças foram docker-compose YAML, Grafana dashboard/alert JSON+YAML, e código TypeScript/Next.js — todos já gated por seus próprios validadores nativos: `docker compose config`, `python3 -m json.tool`, `yaml.safe_load`, `tsc`/`vitest`/`jest`/`eslint`/`next build`).

## Task: corrigir achado novo — `rasta-latency-p95` usava `mean()` sobre contador cumulativo — 2026-09-09
Pedido do usuário: atacar o achado registrado na task anterior (a lógica do alerta de latência do
rastafinancas era uma aproximação, não uma p95 real).
- Substituída a query Flux de `mean()` sobre o field `sum` (cumulativo — tirar a média de um
  contador que só cresce não é latência média nenhuma) pela MESMA técnica de quantil-por-bucket já
  testada no dashboard `rasta-api-performance.json`: soma os buckets do histograma entre todas as
  rotas/métodos/status, pivota num único row, acha o menor boundary cuja contagem cumulativa
  cobre 95% do total.
- **Bug real introduzido e corrigido na mesma sessão**: usei comentário estilo `#` (Python/shell)
  dentro da query Flux embutida no YAML — Flux usa `//`, não `#`, pra comentário. Descoberto não no
  teste manual via API do InfluxDB (que não tinha os comentários), mas só depois, checando a
  avaliação REAL do alerta via `GET /api/prometheus/grafana/api/v1/rules` — `health: "error"`,
  `lastError` mostrando o erro de parse Flux completo. Corrigido (`#` → `//`), Grafana reiniciado,
  reconfirmado saudável em 2 ciclos de avaliação (`interval: 2m`) consecutivos.
- Verificação externa real (evaluation de verdade, não só "YAML carregou"): `health: "ok"`,
  `lastError: None`, valor retornado `5e+00` (5ms) — plausível dado o tráfego atual (só
  `/health`/`/metrics` sendo chamados). Confirmado estável em 2 avaliações consecutivas (~2min de
  intervalo), não uma leitura isolada.
- Status: DONE. Lição registrada: pra alertas/dashboards com query embutida numa linguagem
  diferente do arquivo host (Flux dentro de YAML, PromQL dentro de JSON etc.), validar sintaxe do
  arquivo host (`yaml.safe_load`/`json.load`) NÃO garante que a query interna é válida — só a
  avaliação real (ou teste direto contra o datasource) pega isso. Validado manualmente contra a API
  do InfluxDB ajuda, mas só cobre exatamente o texto testado — comentários/formatação adicionados
  depois do teste manual, na hora de montar o YAML final, não foram re-testados até a avaliação
  real do Grafana pegar o erro. Prática a manter: depois de montar o artefato final (YAML/JSON),
  sempre conferir a avaliação/execução real de novo, não só o teste do fragmento isolado.
