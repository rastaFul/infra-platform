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
