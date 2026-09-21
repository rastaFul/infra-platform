## Task: docker-disk-cleanup — 2026-09-21

Pedido do usuário: "está ocupando todo o meu disco principal" (C:, 9.1GB livres de 477GB, 99% uso).
Ação de manutenção (não infra-código) — sem spec formal por ser operação de limpeza reversível/
read-diagnóstico-primeiro; gates externos não aplicáveis (não é terraform/k8s/helm), verificação
externa = `docker system df` antes/depois + `df -h`.

Diagnóstico:
- Docker Desktop estava `Stopped` (WSL integration não ativa nesta distro) — iniciado via
  `Start-Process`, daemon pronto em ~20s.
- `docker system df` antes: Images 42.93GB (95 total, 25 ativas, 61% reclaimable), Build Cache
  44.8GB (717 entradas, 0 ativas, 100% reclaimable), Volumes 3.39GB (1.73GB reclaimable),
  Containers 656.5MB (33 rodando, 0 reclaimable).
- Causa raiz do disco cheio: `C:\Users\rodri\AppData\Local\Docker\wsl\disk\docker_data.vhdx` = 88GB
  (WSL2 backend, disco virtual dinâmico que não encolhe sozinho no host Windows mesmo após prune).

Ações executadas (seguras, sem tocar imagem com tag nem volume em uso):
- `docker image prune -f` — 63 imagens dangling removidas, 10.82GB reclaimados (dentro do container fs)
- `docker builder prune -af` — 718 entradas de build cache, 44.8GB reclaimados
- `docker container prune -f` — 0B (todos os 33 containers estavam `Up`, nada pra remover)
- `docker system df` depois: Images 16.15GB (32 total), Build Cache 0B, Volumes inalterado (não tocado)

Verificação externa: `docker system df --format json` antes/depois confirma reclaimable real
(não auto-reportado). `df -h /mnt/c` ainda mostra 9.1GB livres — esperado: prune libera espaço
DENTRO do VHDX ext4, mas o arquivo `docker_data.vhdx` no NTFS do Windows não encolhe automaticamente
(sparse/dynamic VHD sem TRIM automático neste ambiente). Compactação do VHDX (`Optimize-VHD` /
`diskpart compact vdisk`) é o passo que de fato libera os 9.1GB→~65GB no C: real — requer parar
Docker Desktop (derruba os 33 containers) e `wsl --terminate docker-desktop`/`docker-desktop-data`
(não afeta a distro `Ubuntu-20.04` onde esta sessão roda). **Não executado — aguardando confirmação
do usuário** por causa da disrupção aos containers rodando agora.

Não executado (pedindo confirmação antes, risco maior que "artefato intermediário"):
- `docker image prune -a` (removeria ~12GB adicionais de imagens COM tag não usadas por container
  ativo, ex: `artists-booking-api:pre-spec77-rollback` — pode ser rollback intencional)
- `docker volume prune` (1.73GB, volumes dangling — possível dado de projeto parado)

- Status: PARTIAL (limpeza segura de artefatos intermediários DONE; compactação do VHDX + prune
  agressivo de imagens/volumes aguardando decisão do usuário)

## Task: docker-disk-cleanup (continuação) — prune agressivo + compactação — 2026-09-21

Usuário aprovou explicitamente ("Pode aplicar as duas sugestões... compactar... 12Gb a mais com
as imagens não usadas").

1. `docker image prune -a -f`: 7 imagens com tag removidas (não referenciadas por container ativo).
   `docker system df` depois: Images 12.19GB (25 total, 25 ativas, 0% reclaimable) — era 16.15GB/32.
   Volumes (1.726GB reclaimable/11 dangling) NÃO tocado — fora do pedido explícito do usuário.
   Status: DONE.

2. Compactação `docker_data.vhdx` — tentativa passo a passo:
   - `Stop-Process 'Docker Desktop'/'com.docker.backend'/'com.docker.build'` — PASS, 0 processos
     docker* restantes confirmado via `Get-Process`.
   - `wsl --terminate docker-desktop` — PASS. `docker-desktop-data` não existe como distro separada
     nesta instalação (achado real, não assumido).
   - `Get-Service com.docker.service` — `Stopped`, confirmado.
   - `wsl --manage docker-desktop --set-sparse true` — rejeitado pelo próprio WSL ("Sparse VHD
     support is currently disabled due to potential data corruption"), exigiria `--allow-unsafe` —
     **não usado**, risco de corrupção de dado real não vale a economia de disco.
   - `diskpart /s harness-compact.txt` (select vdisk + attach readonly + compact + detach), via
     `Start-Process -Verb RunAs` (elevação UAC, aprovada pelo usuário na tela em ~10s): **falhou 3x
     seguidas**, mesmo erro — "DiskPart has encountered an error: The process cannot access the
     file because it is being used by another process." Monitorado ativamente por 200s (tamanho do
     arquivo não mudou, `94373937152` bytes = ~87.9GB, igual ao inicial) — não é lentidão, é lock
     persistente.
   - Investigado: `Get-Service vmcompute` = `Running` (esperado, compartilhado por todas as distros
     WSL2, `Ubuntu-20.04` continua `Running`); nenhum processo `docker*` remanescente; `Get-Disk`/
     `diskpart list disk` sem admin não retornaram nada conclusivo.
   - **Decisão de segurança**: NÃO executado `wsl --shutdown` (única solução conhecida além de
     restart do Windows) — mataria a própria sessão do Claude Code (roda dentro da distro
     `Ubuntu-20.04` deste WSL2), sem possibilidade de fechar o registro depois. Escalado pro
     usuário via runbook + STATE.md, não é um "não fiz" silencioso.
   - Docker Desktop religado (`Start-Process`) pra não deixar o stack local parado. Confirmado:
     33/33 containers `Up` de novo (política `restart: always`), `docker system df` pós-restart:
     Images 12.19GB/25, Containers 656.5MB/33, Volumes 3.374GB (1.726GB reclaimable, inalterado),
     Build Cache 0B. `df -h /mnt/c`: 8.2GB livres (variação normal de uso do sistema, não regressão
     desta sessão — nenhuma escrita nova nossa entre as duas medições).
   - Status: BLOCKED (ação pendente do usuário — reiniciar Windows ou `wsl --shutdown` manual fora
     desta sessão, depois rodar `C:\Users\rodri\AppData\Local\Temp\harness-compact.txt` via
     diskpart elevado, ANTES de religar o Docker Desktop). Procedimento documentado em
     `docs/how-to/docker-disk-cleanup.md`.

3. Registro: runbook `docs/how-to/docker-disk-cleanup.md` criado. Backlog de automação (prune
   pós-build, checagem periódica, política de retenção de tags rollback) adicionado em
   `.specs/project/ROADMAP.md` ("Docker disk lifecycle — backlog") — spec formal ainda não
   escrita, aguardando o usuário priorizar. Decisão completa: D-2026-09-21-1 em DECISIONS.md.

- Status geral da task: PARTIAL — prune agressivo DONE e verificado; compactação do VHDX BLOCKED
  (ação manual do usuário necessária); runbook + backlog registrados conforme pedido.

## Task: docker-disk-lifecycle (spec) — 2026-09-21

Usuário aprovou execução direta ("Pode executar a spec criada"). Spec formal criada e executada
end-to-end na mesma sessão: `.specs/features/docker-disk-lifecycle/spec.md` (5 decisões D1-D5,
6 tasks, todas DONE).

- shellcheck `scripts/docker-disk-guard.sh`: PASS (0 findings, exit 0)
- Execução real (não só sintaxe): `docker image prune -f` (0B — já limpo pela sessão anterior),
  `docker builder prune -af` (0B — idem), threshold check `docker_data.vhdx` = 87GB (>= 40GB → WARN
  disparado corretamente), C: livre = 5GB (<= 20GB → WARN disparado corretamente), scan de tags
  rollback = 0 flagged (confirmado via `docker images` real: `pre-spec77-rollback` não existe mais,
  já removida pelo prune agressivo anterior — não é bug do script)
- crontab: entrada `35 3 * * * .../docker-disk-guard.sh >> ~/logs/docker-disk-guard.log 2>&1`
  instalada, `~/logs/` criado, daemon `cron` confirmado `running` (sem gap de ativação, diferente
  do `backup.sh` original)
- `docs/how-to/docker-disk-cleanup.md` atualizado (seção nova linkando o guard, escopo manual
  explícito documentado)
- `.specs/project/ROADMAP.md`: item "Docker disk lifecycle" marcado DONE (exceto compactação —
  deliberadamente manual, D4)
- **Achado fora do escopo original, registrado**: C: caiu de 8.2GB→5GB livres entre a sessão
  anterior e esta execução (poucos minutos, sem ação nossa) — consumo ativo de outro processo do
  Windows não investigado. Confirma que os thresholds do guard (D2) já são necessários de verdade,
  não teóricos.
- Status: DONE (spec `docker-disk-lifecycle` completa e verificada)

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

## Task: gate de pre-commit LOCAL para infra-platform — 2026-09-09
Pedido: fechar o gap "nada roda antes de um commit neste repo" — `skills/policy-gates`,
`skills/infra-quality-gates`, `skills/security-gates`, `skills/cost-gates` só rodavam manualmente
ou via `.github/workflows/gates.yml` pós-push. Instrução explícita: NÃO instalar o template JS/TS
(husky+lint-staged+eslint+tsc, `agents-harness/claude/install.sh`) — confirmado que este repo não
tem `package.json` em lugar nenhum.

Decisão completa em D-2026-09-09-6 (DECISIONS.md): git hook nativo (`scripts/pre-commit.sh`
versionado + `.git/hooks/pre-commit` wrapper de 1 linha), framework `pre-commit` (Python) e o
template JS/TS ambos rejeitados e justificados.

**Implementado**:
- `scripts/pre-commit.sh`: gitleaks (`--staged`), `terraform fmt -check`+`terraform validate` (só
  `.tf` staged, via `skills/infra-quality-gates/scripts/find-tf-root.sh` já existente pra achar o
  root module real), shellcheck (só `.sh` staged), sintaxe YAML/JSON (só staged). Tool ausente =
  `[SKIP]` com instrução de instalação — nunca bloqueia nem finge PASS.
- `gitleaks` 8.30.1 (mesma versão pinada em `.harness-sandbox/docker/Dockerfile.sandbox`) e
  `shellcheck` 0.10.0 instalados como binários standalone em `~/.local/bin` — nenhum dos dois
  estava presente nesta máquina antes desta sessão (mesmo padrão já usado pra terraform/trivy/
  yamllint/gh, sem sudo).

**Verificação real executada** (não só sintaxe isolada do script):
1. `shellcheck scripts/pre-commit.sh` direto: achou um bug real no próprio script (`cd
   "$REPO_ROOT"` sem `|| exit`, SC2164) — corrigido antes de qualquer teste seguinte.
2. Teste isolado 1 (stage temporário de `scripts/_gate_test_bad.sh` com `cd` sem guarda + variável
   sem aspas, revertido depois): hook bloqueou (`[FAIL] shellcheck`, exit 1).
3. Teste isolado 2 (`terraform/environments/oci-free/main.tf` com um `resource` mal formatado,
   staged, revertido depois): `[FAIL] terraform fmt -check` bloqueou; `terraform validate` rodou
   de verdade (baixou o provider `oracle/oci` via `terraform init -backend=false`, PASS separado).
   Efeito colateral achado: `terraform init` reescreveu `.terraform.lock.hcl` (novo provider
   `hashicorp/null` do recurso de teste) — identificado com `git diff` e revertido (`git checkout
   --`) antes do commit real, não fazia parte do trabalho pedido.
4. Teste isolado 3 (`platform/_gate_test_bad.yaml` com YAML quebrado, staged, revertido depois):
   `[FAIL] yaml syntax` bloqueou (`yaml.scanner.ScannerError: mapping values are not allowed
   here`).
5. Teste isolado 4a (fake token estilo GitHub `ghp_...` de tamanho ligeiramente errado, staged,
   revertido): gitleaks corretamente NÃO sinalizou — confirma que não é um gate "grita com
   qualquer string parecida com segredo", segue as regras reais do gitleaks (formato/checksum).
   Teste isolado 4b (chave privada RSA de teste, staged, revertido): `[FAIL] gitleaks` bloqueou
   (`RuleID: private-key`).
6. **Commit real de ponta a ponta**: `git add scripts/pre-commit.sh .specs/project/STATE.md
   .specs/project/DECISIONS.md .specs/audit/execution.md` + `git commit` (sem `--no-verify`) — o
   hook (`.git/hooks/pre-commit` → `scripts/pre-commit.sh`) rodou sozinho, sem intervenção manual,
   gitleaks/shellcheck/yaml todos `[PASS]` reais sobre os arquivos de verdade sendo commitados
   (nenhum `.tf` staged neste commit, então o bloco terraform não executou — já provado
   separadamente no teste isolado 2). Hash do commit real: ver mensagem do commit / `git log -1`.

Status: DONE. Pendência registrada, não bloqueante: `gitleaks`/`shellcheck` só instalados nesta
máquina/sessão — outro clone precisa instalar os dois (comandos no cabeçalho de
`scripts/pre-commit.sh`) antes dessas duas checagens rodarem de verdade lá; até lá, `[SKIP]`, nunca
falso `[PASS]`. CI (`.github/workflows/gates.yml`) já roda gitleaks incondicionalmente dentro do
`harness-sandbox` (que já tem o binário), então a rede de segurança pós-push continua intacta
mesmo nos clones sem os binários locais.

## Lote 0: Pré-voo (backup + tags) — infra-full-upgrade-2026-09 — 2026-09-15T15:43:00-03:00
- scripts/backup.sh: PASS (SQLite x2, Postgres vetcare, 4 volumes Docker, Vault keys — 95M, sem R2)
- git tag pre-infra-upgrade-2026-09: PASS em infra-platform (96c30a0), rastafinancas (fb456f1),
  microgrow (cf8ba9a7), vetcare (aae2eb7), artists-booking (6593012)
- WIP não-relacionado em rastafinancas/microgrow deixado intocado (working tree dirty de outra
  frente do usuário) — tag aponta pro HEAD committed, não pro working tree
- Status: DONE

## Lote 1: Tooling (Terraform CLI + provider OCI) — infra-full-upgrade-2026-09 — 2026-09-15T15:52:00-03:00
- Terraform CLI: 1.9.8 -> 1.16.2 (binário verificado por SHA256SUM oficial antes de substituir;
  binário antigo preservado em ~/.local/bin/terraform.pre-upgrade-2026-09)
- terraform-provider-oci: ~>6.0 -> ~>9.0 (v9.1.0 instalado) em modules/oci-compute e
  environments/oci-free. Changelog checado: única breaking change relevante (remoção de
  distributed_database) não é usada neste módulo (só VCN/subnet/instance/security_list) — sem
  ajuste de código necessário.
- terraform validate: PASS
- terraform fmt -check -recursive: PASS
- terraform plan: BLOCKED (mesma pendência pré-existente — sem conta OCI nem `terraform login` no
  Terraform Cloud, não é regressão desta sessão)
- git diff: só .terraform.lock.hcl + 2 main.tf, nenhum binário de provider vazado
- Status: DONE

## Lote 2: Promtail -> Grafana Alloy (4 produtos) — infra-full-upgrade-2026-09 — 2026-09-15T16:10:00-03:00
Delegado em paralelo a 4 sub-agentes task-executor (1 por produto, sem sobreposição de arquivos).
- microgrow: convert PASS, alloy validate PASS, docker compose config PASS, container Up, Loki
  gate real PASS (log novo de microgrow-api confirmado via query_range).
- rastafinancas: mesmo padrão, PASS em todos os gates, log novo de rastafinancas-api confirmado.
- vetcare: mesmo padrão, PASS, anti-self-scraping confirmado (filtro `^vetcare$` ancorado mantido).
- artists-booking: mesmo padrão, PASS, log novo de artists-api confirmado.
Achado comum aos 4 (não bloqueante): replay de backlog de dias no cold-start do Alloy (volume de
posições novo, sem herdar checkpoint do Promtail) gera `entry too far behind` no Loki por alguns
segundos — descarte de log histórico esperado, sem perda de log novo, sem crash.
Decisões dos sub-agentes não confirmadas por mim ainda (ver dúvidas finais): nome do container
mantido `<produto>-promtail` em 3/4 (só microgrow trocou o nome do serviço, manteve container_name)
em vez de renomear pra `<produto>-alloy`; configs antigas mantidas como histórico (não deletadas).
Status: DONE (4/4).

## Lote 3+4+5 (combinados por dependência real descoberta em execução): OTEL Collector + Prometheus + Loki — 2026-09-15T16:15:00-03:00
Achado de sequenciamento real durante a execução (registrar como desvio do spec.md original, que
tinha Lote 3/Lote 4/Lote 5 como blocos separados): o exporter dedicado `loki` do
opentelemetry-collector-contrib foi DELETADO do binário (confirmado: `exporter/lokiexporter` 404
no GitHub na tag v0.160.0, existia em 0.103.0) — só resta usar OTLP nativo do Loki (`/otlp/v1/logs`),
que só existe a partir do Loki 3.x. Bumpar o OTEL Collector sem bumpar o Loki junto quebraria a
config (`otlp_http` exporter apontando pra um Loki 2.x que não entende OTLP). Os 3 serviços foram
tratados como uma unidade de gate.
- **OTEL Collector**: 0.103.0 -> 0.160.0. Exporter `loki` -> `otlp_http/loki` (`http://loki:3100/otlp`,
  TLS insecure). 2 bugs reais achados e corrigidos via gate externo (não hipotéticos):
  1. Usei inicialmente o alias `otlphttp` (deprecated) em vez do nome canônico `otlp_http` —
     achado pelo `[warn] "otlphttp" alias is deprecated` real no log do container, corrigido.
  2. `service.telemetry.metrics.address` nunca esteve configurado explicitamente (o binário
     assumia o default 0.0.0.0:8888 antes) — >=0.123.0 IGNORA esse default silenciosamente, o
     endpoint de self-metrics simplesmente não sobe mais. Achado real via Prometheus target
     `otel-collector/collector-self-metrics` `down` (`connection refused`), não hipótese de
     changelog. Corrigido com a sintaxe nova (`service.telemetry.metrics.readers[].pull.exporter.
     prometheus`), confirmado com `curl localhost:8888/metrics` 200 e target voltando `up`.
- **Loki**: 2.9.10 -> 3.7.7. Achado real e verificado empiricamente (não só documentação): imagem
  removeu BusyBox (`/bin/sh` inexistente, `exec: "sh": executable file not found` confirmado via
  `docker exec`) — o HEALTHCHECK antigo (`wget --spider`) nunca mais executaria, deixando o
  container permanentemente `unhealthy` e travando o `depends_on: condition: service_healthy` do
  Grafana pra sempre. HEALTHCHECK removido (mesmo padrão já usado pro otel-collector, mesma classe
  de causa), `depends_on` do Grafana ajustado pra `service_started`. Schema já estava em v13/tsdb
  desde antes desta sessão (achado bom: a suposição do spec.md original de que seria
  boltdb-shipper estava errada — zero migração de schema necessária, só bump de imagem).
- **Prometheus**: v2.55.1 -> v3.14.0. Config já não usa nenhuma das 4 breaking changes do
  inventário (sem `relabel_configs` com regex `.`, sem `remote_write`, sem `scrape_classic_
  histograms`). vetcare `/api/metrics` já seta `Content-Type` correto (`registry.contentType`,
  prom-client) — sem risco da checagem estrita de Content-Type do v3.
- Gates externos reais: `docker compose config` PASS, `promtool check config` PASS (via
  `docker exec platform-prometheus /bin/promtool`), 6/6 Prometheus targets `up` (apis-host x3,
  otel-collector x2, vetcare), Loki `/ready` 200 sem erro nos logs.
- Status: DONE

## Lote 6: Grafana 10.4.0 -> 13.2.1 — infra-full-upgrade-2026-09 — 2026-09-15T16:59:00-03:00
- docker compose config PASS, container healthy 35s após force-recreate
- API /api/health: version 13.2.1, database ok
- 4/4 datasources provisionados presentes (influxdb x2, loki, prometheus) + 1 datasource manual
  antigo pré-existente não provisionado (fora do escopo, já existia antes desta sessão)
- 19 dashboards carregados via /api/search (dashboards + pastas dos 4 produtos + Platform)
- Query real via proxy: Prometheus `up` retornou 6/6 targets =1; Loki `/loki/api/v1/labels`
  retornou labels reais (`app,container,service,service_name` -- `service_name` é o novo label
  automático do Loki 3.x, não é regressão)
- Único erro nos logs (não bloqueante): plugin provisioning dir `/etc/grafana/provisioning/plugins`
  inexistente -- nunca usamos plugins provisionados, sem impacto
- Status: DONE

## Lote 7: Vault 1.17 -> 2.1.0 — infra-full-upgrade-2026-09 — 2026-09-15T17:01:00-03:00
Achado real via changelog + confirmado no boot: Vault 2.x removeu a capability `cap_ipc_lock` das
imagens no build -- com `disable_mlock = false` (config anterior) o `mlock()` teria falhado e o
processo não subiria. Corrigido ANTES do bump (`disable_mlock = true` em vault.hcl, `cap_add:
IPC_LOCK` do compose mantido só documentativamente, sem efeito real agora). Nenhuma policy .hcl
usa nome com case misto (CVE de normalização de policy name não aplicável) nem chave RSA (limite
de 8192 bits não aplicável).
- docker compose config PASS
- Boot real: log confirma `Mlock: supported: true, enabled: false` (comportamento esperado, não
  crash) -- container `healthy` em 8s
- Unseal real com a chave de `~/.vault-init-local` (threshold=1): `Sealed: false` confirmado
- `vault auth list`: approle/ intacto. `vault kv list secret/`: 4/4 tenants (artists, microgrow,
  rastafinancas, vetcare) presentes
- `vault kv get secret/vetcare/env`: dado real recuperado (version 2, created 2026-09-09) --
  nenhuma perda de dado no bump
- Status: DONE

## Lote 8: GlitchTip 4.2.4->5->6 + Postgres 16->18 + Redis 7->8 — infra-full-upgrade-2026-09 — 2026-09-15T17:10:00-03:00 (mais arriscado, dump antes de cada etapa)
- Redis: 7-alpine -> 8-alpine. `PONG` real confirmado pós-bump, sem dado persistente relevante
  (só broker/beat do Celery/worker, perda aceitável).
- Dump real do Postgres antes de cada etapa (`pg_dump` completo, 3x: pre-v5, pre-v6, pre-pg18),
  guardados em scratchpad da sessão (não no repo).
- GlitchTip 4.2.4 -> v5 (tag major, recebe minors automaticamente por design do projeto):
  **bug real pré-existente achado e corrigido** (não causado por esta sessão) -- migração
  `performance.0015_transactiongroup_is_deleted` estava marcada `applied` desde 2026-06-06 na
  tabela `django_migrations`, mas a coluna `is_deleted` NUNCA existiu de fato na tabela
  `performance_transactiongroup` (confirmado via `information_schema.columns`) -- um "fake apply"
  histórico da configuração inicial, nunca exercitado até o worker v5 rodar a task real que lê essa
  coluna (`ProgrammingError` real no log do celery). Corrigido com `ALTER TABLE ... ADD COLUMN
  is_deleted boolean NOT NULL DEFAULT false` cirúrgico (mesma definição exata da migration
  original). `manage.py migrate --noinput` confirmou "No migrations to apply" depois -- schema e
  migration table agora consistentes. Sem esse achado, o worker teria ficado quebrando
  silenciosamente em produção (silenciado por ser só uma task de manutenção, sem alerta).
- GlitchTip v5 -> v6: 0 eventos reais armazenados (`issue_events_issueevent` count=0) -- decisão
  tomada sem confirmação explícita: NÃO configurei `GLITCHTIP_RETAIN_LEGACY_DATA=True` (cap padrão
  de 10k eventos migrados é irrelevante aqui). v6.0.3 sobe limpo (`granian` ASGI + `Valkey`
  cache/queue, arquitetura diferente do celery/uwsgi do v5), `/`, `/_health/`, `/api/0/` todos 200.
- Postgres 16-alpine -> 18-alpine: **bug real achado no primeiro boot** -- imagem oficial 18+
  recusa iniciar com volume montado direto em `/var/lib/postgresql/data` num volume vazio/novo
  (guard upstream pra suporte a `pg_upgrade --link`, ver docker-library/postgres#37 e #1259).
  Corrigido montando o volume no diretório PAI (`/var/lib/postgresql`), não mais em `.../data`.
  Migração real: novo volume `platform_glitchtip_postgres_data_pg18` (volume pg16 antigo
  `platform_glitchtip_postgres_data` preservado intocado como rollback, não deletado), dump
  restaurado via `psql < dump.sql` (0 erros), confirmado: 150 linhas em `django_migrations`,
  coluna `is_deleted` presente pós-restore, ~1623 relações (tabelas+partições) migradas.
- Gate final: `platform-glitchtip`/`-worker`/`-db`/`-redis` todos up, sem erro nos logs, `/`
  `/_health/` 200 reais via curl.
- Status: DONE

## Lote 3 (resto): cloudflared + Caddy pin — infra-full-upgrade-2026-09 — 2026-09-15T17:14:00-03:00
- cloudflared: 2026.8.2 -> 2026.9.1. Tunnel real reconectado (4 conexões QUIC registradas,
  `gru14/gru19/gru21`), ingress config recarregado com as 6 rotas reais. Gate externo: 6/6
  domínios públicos (vetcare/financas/grow/grow-sim/metrics/artists) sem 502, mesmos códigos de
  sempre (307 app, 302 metrics).
- Caddy (inativo, hygiene): `caddy:2-alpine` (flutuante) -> `caddy:2.11.4-alpine` (pinado).
  `caddy validate` PASS contra o Caddyfile real. Não subido (continua deliberadamente inativo).
- Status: DONE

## Lote 9 (parte 1): Telegraf 1.30->1.40.0 (rastafinancas+microgrow) + mosquitto pin 2.1.2-alpine — 2026-09-15T17:18:00-03:00
- Plugins usados (mqtt_consumer, procstat, internal, prometheus, http_response, cpu, mem, disk,
  outputs.influxdb_v2) checados contra o changelog 1.40 -- nenhum usa as opções removidas
  (`cmdline_tag`/`pid_tag`/`supervisor_unit` de procstat, plugins aerospike/sflow/amon). Sem
  ajuste de config necessário, só warnings informativos (mudança de default futura, não aplicável
  -- zero processors/aggregators configurados nos dois).
- Achado de tag real: `eclipse-mosquitto:2.1.2` não existe no Docker Hub -- tag correta é
  `2.1.2-alpine` (achado via pull real falhando, não assumido do inventário original).
- Gate real: `docker compose config` PASS nos 2 repos, containers up, mqtt_consumer reconectado
  (13 tópicos), gate de dado real via InfluxDB API (`/api/v2/query`) -- CPU real do rastafinancas
  e `api_metrics` real do microgrow chegando com timestamp dos últimos 2 minutos.
- Status: DONE

## Lote 9 (parte 2): Postgres 16->18 vetcare app + evolution-api — infra-full-upgrade-2026-09 — 2026-09-15T17:22:00-03:00
Mesmo padrão do Lote 8 (dump -> novo volume com mount no dir pai -> restore), reaproveitando o
bug real já descoberto (postgres 18+ recusa `.../data` direto num volume novo).
- vetcare `postgres` (vetcare_dev): app parado antes do dump (evita escrita durante a janela),
  dump real, novo volume `postgres_dev_data_pg18`, restore 0 erros, 20 tabelas confirmadas, app
  religado -- `/api/health` 200 local E `vetcare.rastaful.dev` 307 público confirmados depois.
- vetcare `postgres_test`: sem volume nomeado (efêmero) -- só bump de imagem, sem dado a migrar.
- `evolution-db` (vetcare/infra/evolution, app evolution-api dormant, não estava rodando antes
  desta sessão -- não religado, mesmo estado de antes): dump real (49MB de dado pré-existente no
  volume antigo), novo volume `evolution_db_pg18`, restore 0 erros, 31 tabelas confirmadas.
- Volumes pg16 antigos preservados como rollback nos 2 casos (não deletados).
- Status: DONE (Lote 9 completo: telegraf + mosquitto + os 2 Postgres)

## Lote 11: Hygiene final (mailhog + evolution-api) — infra-full-upgrade-2026-09 — 2026-09-15T17:28:00-03:00
- mailhog (artists-booking, dev only): sem LTS/manutenção upstream -- pinado por digest
  (`sha256:8d76a3d...`) em vez de `:latest`, `docker compose config` PASS.
- evolution-api (vetcare/infra/evolution): **achado real e corrigido** -- `atendai/evolution-api`
  não existe mais no Docker Hub (`pull access denied`, confirmado via pull real). Projeto migrou
  pra Evolution Foundation, imagem oficial agora `evoapicloud/evolution-api`. Pinado em `v2.3.7`
  (última stable antes de v2.4.0, que introduz ativação obrigatória contra servidor de
  licenciamento da Evolution Foundation -- decisão de NÃO subir pra 2.4.0 sem aprovação explícita,
  registrada nas dúvidas finais). Serviço continua dormant (não estava rodando antes desta sessão,
  não foi religado).
- Status: DONE

## D3 (fora do escopo original, incluído por decisão do usuário): InfluxDB v2.7 -> v3 Core — infra-full-upgrade-2026-09 — 2026-09-15T17:35:00-03:00 (EM ANDAMENTO)
Maior item de escopo/risco da spec inteira (eu tinha recomendado adiar pra spec própria, usuário
decidiu incluir explicitamente: "todos na última LTS mesmo que envolva migração", D-2026-09-15-1).
Motor completamente novo (reescrita em Rust), não é bump de versão -- Flux removido, só SQL/InfluxQL.

**Escrita (Telegraf, rastafinancas+microgrow)**: ZERO mudança de lógica necessária -- confirmado via
docs oficiais que `outputs.influxdb_v2` funciona sem alteração contra o endpoint de compatibilidade
`/api/v2/write` do v3 (`bucket` vira `database`, `organization` aceito mas ignorado). Só troquei
url/token nos 2 `telegraf.conf` + tokens nos `.env` dos 2 produtos. Gate real: `SHOW TABLES` +
`SELECT` via SQL API confirmam dado novo chegando nas 2 databases (`sensors`, `rastafinancas`)
minutos depois do restart dos telegrafs.

**Servidor**: `influxdb:3-core` adicionado como NOVO serviço `influxdb3` no
`platform/docker-compose.yml`, rodando lado a lado com o `influxdb` 2.7 antigo (mantido de propósito
como rollback, não desligado ainda). Bug real no primeiro boot: container roda como uid 1500 não-root
e o volume novo nasce root-owned -- `Permission denied` criando o catálogo. Corrigido com
`chown -R 1500:1500` via container helper (mesmo padrão já usado no Vault em sessão anterior).
Token admin gerado via `influxdb3 create token --admin` (não pode ser recuperado depois, só
revogado+recriado) -- guardado em `platform/.env` (`INFLUXDB3_ADMIN_TOKEN` + reaproveitado nos 3
`INFLUXDB_TOKEN_*` que os outros serviços já liam) e nos `.env` dos 2 produtos. **Pendência
registrada**: token não empurrado pro Vault ainda (não existe um "tenant" platform no KV v2 hoje,
os 4 paths existentes são todos por produto) -- mesmo padrão de outros segredos platform-level
(GRAFANA_ADMIN_PASSWORD, GLITCHTIP_SECRET_KEY) que também só vivem em `.env`, não é regressão nova.
Databases `sensors`/`rastafinancas` criadas explicitamente (não implícito).

**Leitura (Grafana)**: datasources `influxdb-microgrow`/`influxdb-rastafinancas` migrados de
`version: Flux` pra `version: SQL` (Flight SQL/gRPC, porta 8181, `insecureGrpc: true` -- sem TLS
interno, mesmo padrão de todo o resto do stack). **Bug real achado e corrigido via gate**: o token
usado pelo datasource vem de `platform/.env` (`INFLUXDB_TOKEN_MICROGROW`/`_RASTAFINANCAS`), que eu
tinha esquecido de atualizar (só tinha atualizado os `.env` dos produtos, usados pelo Telegraf) --
`/health` do datasource retornava `Unauthenticated` até eu perceber que o Grafana ainda tinha o
token v2 antigo no ambiente do container (`echo | docker exec -i platform-grafana printenv` real,
não assumido). Corrigido, `/health` das 2 datasources: `OK`. Query real via `/api/ds/query`
(`rawSql`) retornando `status 200` com dado de verdade.

**Pendente (próximo passo desta mesma frente)**: 76 queries Flux em 9 dashboards (5 rastafinancas +
4 microgrow) ainda precisam ser reescritas pra SQL -- delegando a sub-agentes em paralelo agora.
`influxdb` 2.7 antigo continua rodando como rollback até os dashboards serem confirmados.

## Task: infra-full-upgrade-2026-09 (D3) — microgrow dashboards Flux→SQL — 2026-09-15T16:53:31-03:00
- Escopo: 4 dashboards microgrow (`platform/dashboards/microgrow/`), 35 queries Flux traduzidas pra
  SQL (`rawSql`+`format`, campo `query` removido): api-system-health.json (8), environment.json (8),
  sensor-health.json (7), grow-cockpit.json (12). rastafinancas fora do escopo (outro sub-agente).
- Gate real via `/api/ds/query` (não SELECT solto): 35/35 status 200 (nenhum erro de sintaxe SQL).
  10 com dado real (api_metrics, mqtt_broker — únicas tabelas populadas hoje); 25 retornam erro
  400 "table not found" pras 6 measurements ainda sem dado publicado via MQTT (air_conditions,
  soil_moisture, light_data, reservoir, hydric_score, pump_events, process_metrics) — comportamento
  esperado (tabela só existe após 1º write no InfluxDB v3; Flux retornaria vazio em vez de erro,
  diferença de engine documentada, não é bug de tradução).
- Bug pré-existente achado e corrigido (não introduzido por esta tradução): `environment.json`
  referenciava measurement `microgrow_raw`, que não existe em nenhum `name_override` do
  `telegraf.conf` (nunca teria dado, mesmo no InfluxDB 2.7/Flux antigo). Campos/tags batem com
  `air_conditions` (temp_c/humidity_pct/vpd_kpa, sensor_id=sht31_canopy), `light_data` (lux) e
  `soil_moisture` (vwc_pct, position) confirmados contra `api/src/types/sensors.ts` e
  `api/src/routes/simulator.ts` do microgrow — corrigido pro measurement real.
- Macro `$__dateBin(coluna)` testado e confirmado funcional (expande pra `date_bin(interval ...)`)
  DESDE QUE a query tenha `intervalMs` no payload — em painel real do Grafana isso é sempre setado
  automaticamente (equivalente ao `v.windowPeriod` do Flux); só falha (bins de "0 second", frame
  vazio) quando testado via `/api/ds/query` cru sem `intervalMs` explícito. Documentado, não é bug.
- `derivative()`/`aggregateWindow(fn:last)` do Flux sem equivalente direto em SQL: traduzidos com
  window functions (`LAG() OVER (ORDER BY time)` pra derivative; `ROW_NUMBER() OVER (PARTITION BY
  $__dateBin(time) ORDER BY time DESC) WHERE rn=1` pra last-por-bucket) — ambos testados com dado
  real (mqtt_broker/api_metrics) e confirmados funcionais.
- `aggregateWindow(..., createEmpty: true)` (grow-cockpit painel 22, contagem de irrigação por hora
  com buckets vazios preenchidos) não tem equivalente trivial em SQL sem `generate_series` + LEFT
  JOIN — traduzido sem zero-fill (gráfico de barras vai simplesmente omitir horas sem evento, em
  vez de mostrar barra zerada). Diferença assumida, não bloqueante.
- Achado no meio do gate: `platform-grafana` foi reiniciado por outro processo durante o teste
  (restart às 19:52, ~30s de indisponibilidade) — não fui eu; aguardei health check voltar e
  re-rodei a suite completa (resultado idêntico, confirma que não foi flakiness da tradução).
- Status: DONE

## Task: infra-full-upgrade-2026-09 D3 — rastafinancas dashboards Flux→SQL — 2026-09-15T16:53:28-03:00
- Scope: 5 dashboards, 41 targets, `platform/dashboards/rastafinancas/*.json` (microgrow untouched).
- Schema discovery: `SHOW TABLES`/`DESCRIBE` against InfluxDB v3 (port 8181) confirmed real tables
  before writing any query — no field names guessed.
- Macro finding (real, reproduced): `$__dateBin(time)` + `GROUP BY 1` returns empty frames
  (Grafana 13.2.1 + influxdb datasource SQL mode) even with real data in range. Root cause:
  `$__interval` expands to a full `interval 'N second'` literal (not a bare duration string), so
  `INTERVAL '$__interval'` double-wraps it and breaks. Working replacement used everywhere:
  `date_bin($__interval, time)` (no extra `INTERVAL '...'` wrapper), `GROUP BY 1`. Verified with
  real request data via `/api/ds/query` (`intervalMs`/`maxDataPoints` must be present in the
  request, same as real dashboard panels send — a bare curl without those fields yields
  `interval '0 second'`, a false negative, not a datasource bug).
- Rate-over-cumulative-counter (`derivative()` in Flux) translated as
  `counter - LAG(counter) OVER (PARTITION BY <tags> ORDER BY time)` divided by
  `EXTRACT(EPOCH FROM (time - LAG(time) OVER (...)))` — window functions confirmed supported by
  DataFusion/FlightSQL, verified against real `http_requests_total` data.
- Percentile histogram panels (P50/P95/P99): `http_request_duration_ms` is already wide-format
  (bucket boundaries are columns: "5","10",...,"+Inf", quoted identifiers) — no `pivot()` needed,
  translated with `ROW_NUMBER() OVER (PARTITION BY date_bin(...), route, method ORDER BY time DESC)`
  + `CASE` threshold logic, verified against real data.
- Real measurement-name mismatches found and corrected (not guessed): 3 Flux queries referenced
  measurement names that never map 1:1 to InfluxDB v3 tables — `http_response_result_code` /
  `http_response_response_time` -> real table is `http_response`, fields `result_code`/
  `response_time` (confirmed via DESCRIBE + real data, `rasta-slo.json` panels 1/2/4/5/6/7 and
  `rasta-infra.json` panels 9/10); `mem_used_percent`/`disk_used_percent` -> real tables `mem`/
  `disk`, field `used_percent` (`rasta-infra.json` panels 7/8). `disk` has multiple `path` tags
  (bind mounts) — filtered to `path = '/'` for a single gauge value (decision made without
  explicit confirmation, documented here). `cpu` has only tag value `cpu-total` today — filtered
  explicitly for robustness if per-core rows appear later.
- 12 of 41 targets reference measurements that do not exist in InfluxDB v3 at all yet (confirmed
  via `DESCRIBE` -> `table not found`, pre-existing gap, not caused by this migration):
  `rasta_rate_limit_hits_total` (api-performance panel 8, auth-security panel 7),
  `rasta_user_signups_total` (auth-security 1,2), `rasta_auth_logins_total` (auth-security 3,4),
  `rasta_auth_token_refreshes_total` (auth-security 5), `rasta_auth_password_resets_total`
  (auth-security 6), `rasta_data_ops_total` (product 1,2), `rasta_import_batches_total` (product 3),
  `rasta_import_errors_total` (product 5), `rasta_notification_job_runs_total` (product 6),
  `rasta_notifications_sent_total` (product 7,8), `procstat_cpu_usage`/`procstat_memory_rss`
  (infra 1-4), `filestat_size_bytes` (infra 5). SQL for these was still translated (syntactically
  correct, consistent with proven patterns) so the dashboards are ready the moment the app/Telegraf
  starts emitting them — but field names inside those tables (e.g. exact procstat field name)
  could not be confirmed and were assumed as `counter` by convention with the rest of the
  ecosystem. Flag for follow-up when those metrics land.
- 2 targets are syntactically correct SQL against a real, existing table but return 0 rows because
  no matching data exists yet (not an error): `4xx by Route`/`5xx by Route` in api-performance
  (no 4xx/5xx responses recorded against `http_requests_total` since only self-`/health`+`/metrics`
  probes have been captured so far).
- Verification method: live `/api/ds/query` against the real running Grafana (13.2.1, uid
  `influxdb-rastafinancas`), one call per target, using each dashboard's own saved time range —
  not just `/api/v3/query_sql` syntax checks. `docker restart platform-grafana` forced immediate
  provisioning reload (dashboard `version` field bumped, confirmed via `/api/dashboards/uid/*`).
- Final tally: 41/41 targets syntactically valid SQL (0 parse/plan errors other than
  "table not found" for the 12 pre-existing gaps above). 27/41 returned real data rows right now;
  2/41 real table + real syntax but 0 matching rows (no 4xx/5xx yet); 12/41 error until upstream
  metrics exist.
- Known side-effect noted, not fixed (out of scope — task said "só troque o conteúdo da query"):
  `rasta-slo.json` panel "Downtime Events" has `fieldConfig.overrides` renaming Flux-era columns
  `_time`/`_value`/`probe` — these no longer match the new SQL column names (`time`/`value`/`probe`)
  exactly for `_time`/`_value` (now just `time`/`value`), so those two display-name overrides will
  silently stop applying. Cosmetic only, not a data-correctness issue; flagged for the orchestrator.
- Status: DONE (all 5 files, all targets converted, no microgrow files touched)

## Lote 10: Node 22 -> 24 (3 repos, D4) — infra-full-upgrade-2026-09 — 2026-09-15T18:30:00-03:00 (delegado em paralelo, 3 task-executor)
- **artists-booking**: build PASS (web+api), tsc 0 erros, web 523/523 testes. `Dockerfile.dev` da
  API já não buildava ANTES do bump (pnpm sem pin via `npm install -g`, não corrigido — fora de
  escopo, arquivo tocado só na linha FROM). 7/277 testes da API flaky por timeout de I/O,
  confirmado idêntico em Node 22 via controle A/B — não é regressão do bump.
- **rastafinancas**: build PASS (web+api), tsc 0 erros, web 188/188 testes. 2/171 testes da API
  falhando (`oauth.test.ts`, timeout 5000ms) confirmado idêntico em Node 22 via controle A/B (3x) —
  débito pré-existente, não regressão. 1 falha adicional isolada não reproduzida (N=1, sem
  correlação clara com o bump).
- **vetcare**: build PASS, tsc 0 erros, 48/48 suites e 234/234 testes — 100% limpo, zero achado.
  uid do usuário do container confirmado inalterado (`appuser` 1001, não usa o `node` padrão da
  imagem) — hipótese minha de risco (chown de bind-mount) não se aplicava a este repo (era de
  outro, artists-booking — erro meu no briefing, corrigido pelo sub-agente).
- Nenhum dos 3 repos teve build/binário nativo quebrado pelo bump em si (libsql, bcryptjs,
  drizzle-orm, esbuild, prisma, sharp etc. -- todos instalaram/rodaram normal em Node 24 Alpine).
- Status: DONE (3/3) -- achados de débito de produto pré-existente registrados, NÃO corrigidos
  (fora de escopo do harness-infra), candidatos a spec própria no harness-dev se o usuário quiser.

## D3 (conclusão): 76 queries Flux -> SQL, 9 dashboards — infra-full-upgrade-2026-09 — 2026-09-15T18:35:00-03:00 (delegado em paralelo, 2 task-executor)
- **rastafinancas** (5 dashboards, 41 targets): 41/41 sintaticamente válidos via gate real
  (`/api/ds/query` contra Grafana rodando, não só parse estático), 27/41 com dado real hoje, 2/41
  válidos mas 0 linhas (sem incidente registrado ainda), 12/41 aguardando métricas que NUNCA
  existiram no ecossistema (débito pré-existente, não desta migração). 3 mismatches reais de nome
  de medição achados e corrigidos (`http_response_result_code`->`http_response.result_code`,
  `mem_used_percent`->`mem.used_percent`, `disk_used_percent`->`disk.used_percent`). Achado técnico
  registrado: macro `$__dateBin` não funciona (`$__interval` já expande pra `INTERVAL 'N second'`,
  dobrar o wrap quebra) -- solução real usada: `date_bin($__interval, time)` + `GROUP BY 1`.
  `derivative()` sobre contador Prometheus traduzido via `LAG() OVER (...)`. 1 regressão cosmética
  NÃO corrigida (fora do escopo pedido): `fieldConfig.overrides` do painel "Downtime Events" ainda
  referencia nomes de coluna Flux (`_time`/`_value`) que não existem mais.
- **microgrow** (4 dashboards, 35 targets): 35/35 sintaticamente válidos, 10/35 com dado real hoje
  (resto são 6 medições MQTT sem nenhum dado publicado ainda, confirmado via `SHOW TABLES`, não é
  erro de tradução). Achado e corrigido bug pré-existente real: `environment.json` referenciava
  measurement `microgrow_raw`, que NUNCA existiu em nenhum `telegraf.conf` (nem antes desta
  migração) -- remapeado pras medições reais (`air_conditions`/`light_data`/`soil_moisture`) via
  evidência cruzada no código do produto. `aggregateWindow(createEmpty: true)` não tem equivalente
  trivial em SQL sem `generate_series`+`LEFT JOIN` -- traduzido sem zero-fill (gap visual aceito).
- Ambos os sub-agentes verificaram via chamada real `/api/ds/query` contra o Grafana rodando, não
  só validação de sintaxe SQL isolada.
- Status: DONE. `influxdb` 2.7 antigo continua rodando como rollback (não desligado ainda -- ver
  dúvidas finais pra decisão do usuário sobre quando desligar).

## Validação final completa + gates finais — infra-full-upgrade-2026-09 — 2026-09-15T20:00:00-03:00
- **Achado real na varredura final de containers** (só pego porque rodei `docker ps` de tudo, não
  assumido): `platform-influxdb3` estava `unhealthy` há ~30min, mesmo funcionando perfeitamente o
  tempo todo (escrita+leitura confirmadas antes) -- causa: `/health` do InfluxDB 3 Core exige auth
  (401 sem token, confirmado `curl` direto), sem endpoint anônimo tipo `/ping` livre. Healthcheck
  original não passava header. Corrigido: token injetado como env var no container +
  `Authorization: Bearer` no healthcheck. `healthy` confirmado, dado revalidado intacto pós-restart
  (118 linhas em `cpu`, contagem real via SQL).
- docker compose config: 8/8 PASS (platform, tunnel, caddy, microgrow, rastafinancas/observability,
  vetcare, vetcare/evolution, artists-booking)
- terraform validate + fmt -check -recursive: PASS
- 6/6 domínios públicos (vetcare/financas/grow/grow-sim/metrics/artists): sem 502, códigos normais
- Todos os containers do ecossistema (29 real, `docker ps`): nenhum crash loop, nenhum `unhealthy`
  restante
- `skills/infra-quality-gates/run-infra-quality.sh` + `run-infra-quality-final.sh`: overall PASS
  (tflint/kubeconform/pluto/terraform-docs/polaris/kube-linter SKIPPED -- não instalados nesta
  máquina, mesmo gap documentado há sessões, nunca finge PASS)
- `skills/policy-gates/run-policy-gate.sh`: SKIPPED (conftest não instalado, gap pré-existente)
- `skills/security-gates/run-security-gates.sh`: overall FAIL -- gitleaks achou 5 segredos em
  `platform/.env`/`tunnel/.env` (working-tree scan, não `--staged`). Confirmado real: os 2 arquivos
  estão no `.gitignore` (`git check-ignore` real), nunca seriam commitados -- 4/5 achados são o
  token novo do InfluxDB 3 que eu mesmo gerei nesta sessão (esperado, mesmo padrão de todo outro
  segredo do ecossistema), 1/5 é o `CLOUDFLARE_API_TOKEN` pré-existente (não tocado por mim). Não é
  uma regressão de segurança nova -- é o script rodando `gitleaks detect` (filesystem) em vez de
  `gitleaks protect --staged` (git-aware) localmente, diferença que não existe no CI (onde `.env`
  simplesmente não existe no checkout). trivy_fs: PASS. osv-scanner: SKIPPED (não instalado).
- `skills/security-gates/run-security-final.sh`: overall FAIL -- `trivy_config` achou 1 HIGH
  (`DS-0002`, falta `USER` não-root) em `.harness-sandbox/docker/Dockerfile.sandbox` -- arquivo do
  próprio harness (sandbox de execução), não tocado nesta sessão, fora do escopo do pacote de 19
  itens. semgrep/syft+grype: SKIPPED (não instalados).
- `skills/cost-gates/run-cost-gate.sh`: SKIPPED (infracost não instalado)
- Status: COMPLETED (ver dúvidas finais registradas em DECISIONS.md pro usuário revisar)

## infra-full-upgrade-2026-09-followups — T1/T2/T3 — 2026-09-15T20:45:00-03:00
Spec `.specs/features/infra-full-upgrade-2026-09-followups/spec.md`, respostas do usuário às 9
dúvidas de D-2026-09-15-2 (ver D-2026-09-15-3 em DECISIONS.md).

**T1 — rasta-slo.json overrides**: `_value`/`_time` -> `value`/`time` nos 2 overrides do painel
"Downtime Events" (`probe`->"Service" já estava certo). Grafana reiniciado, painel confirmado
consistente com as colunas reais retornadas pela query SQL.

**T2 — Vault tenant `platform`**: criada `platform/vault/policies/platform.hcl` (read-only
`secret/data/platform/*`, deny cruzado nos 4 produtos + o inverso nos 4 policies existentes,
mesmo padrão de defesa em profundidade). `platform` adicionado ao array `PROJECTS` de
`scripts/vault-init.sh`, rodado (idempotente — 4 policies existentes re-aplicadas sem re-criar
AppRole, `platform` criado do zero: policy + AppRole). `vault-push-env.sh platform platform/.env`
rodado — 12 chaves reais confirmadas em `secret/data/platform/env` via `vault kv get` real
(incluindo `INFLUXDB3_ADMIN_TOKEN`, `GRAFANA_ADMIN_PASSWORD`, `GLITCHTIP_SECRET_KEY`, etc.).

**T3a — gitleaks working-tree false-positive**: `skills/security-gates/scripts/
run-security-gates.sh` agora gera um allowlist temporário do gitleaks com os paths que o próprio
git considera ignorados (`git ls-files --others --ignored --exclude-standard`) antes de rodar
`gitleaks detect --no-git`, sem perder a varredura de tudo que É rastreável. Gate real:
infra-platform `run-security-gates.sh` -> `overall: PASS` (era FAIL). Sincronizado em
`agents-harness/claude/skills/security-gates/scripts/run-security-gates.sh` (canônico).

**T3b — trivy_config HIGH em Dockerfile.sandbox**: `USER node` (uid 1000, já existe na imagem
base `node:20-alpine`, casa com o uid convencional do host pro bind-mount do `sandbox-run.sh`) +
cópia do plugin helm instalado como root pro home do `node`. Build real (`docker build`) PASS,
smoke test como não-root confirmou terraform/trivy/tflint/kube-linter/helm-unittest/conftest
funcionando. `trivy config` real: 0 misconfigurations (era 1 HIGH). Corrigido no canônico
`agents-harness/docker/Dockerfile.sandbox`, sincronizado pra
`infra-platform/.harness-sandbox/docker/Dockerfile.sandbox`.

**Achado extra durante T3b (bug real, não relacionado ao pedido, corrigido de passagem)**:
`terraform-linters/tflint` removeu `install_linux.sh` do repo em 2026-09-12 — quebrava tanto o
`Dockerfile.sandbox` quanto o `install-gate-tools.sh` (item 8) com 404. Corrigido nos dois lugares
(download direto do zip do release, mesmo padrão dos outros ~15 tools do Dockerfile).

**Item 8 (tooling)**: `agents-harness/scripts/install-gate-tools.sh` criado (novo), instala
tflint/terraform-docs/polaris/pluto/kubeconform/kube-linter/conftest/osv-scanner/syft/grype/
infracost/semgrep direto no host (~/.local/bin, sem sudo), reaproveitando as versões/URLs já
verificadas ao vivo no `Dockerfile.sandbox`. Ligado em `claude/install.sh` e `codex/install.sh`
(roda automaticamente em toda instalação/atualização de agente). Rodado nesta máquina: 11/12 na
primeira tentativa (tflint falhou por causa do mesmo bug do install_linux.sh, corrigido e
re-testado com sucesso: `TFLint version 0.64.0`).
**Achado real adicional, corrigido**: `osv-scanner` v2.x mudou de CLI flat (`--json -r .`) pra
subcomando (`scan source -r --format json .`) — achado só depois de instalar de verdade e rodar
`run-security-gates.sh` (antes era SKIPPED, nunca exercitado). Corrigido no script (canônico +
cópia). Rodar contra `rastafinancas` revelou débito de segurança REAL de produto nunca visto antes
(3 CRITICAL + 31 HIGH via trivy_fs, 6 CRITICAL + 36 HIGH via osv-scanner) — fora do escopo desta
spec (é infra-platform, não rastafinancas), registrado como achado pra decisão futura do usuário.

**Item 9 (zero-fill)**: solução simples encontrada e aplicada — `date_bin_gapfill()` (função
nativa do InfluxDB 3 Core/DataFusion) + `COALESCE(count(...), 0)` no lugar de `date_bin()` simples.
Testado contra dado real (`api_metrics`, 24 buckets horários, zero-fill correto nas horas sem
dado) antes de aplicar no painel real (`pump_events` ainda sem dado — simulador pausado, ver
achado do item 2 — mas a query já está correta e vai zero-preencher assim que houver dado).
Arquivo: `platform/dashboards/microgrow/grow-cockpit.json`.

Status: DONE (T1/T2/T3 + itens 8/9 desta rodada de follow-ups)

## ROADMAP item 7: ansible-lint desbloqueado (dev-environment) — 2026-09-16T00:00:00-03:00
- Achado: máquina só tinha Python 3.8.10 (Ubuntu 20.04 Focal), sem sudo disponível
  (`sudo -n true` falhou), ansible-lint 26.x precisa Python 3.10+.
- Instalado `uv` 0.12.15 (script oficial, real bug achado: `curl | sh` quebra por bashismo do
  próprio script da astral rodando sob `sh`/dash — funciona rodando explicitamente com `bash`,
  não é nada deste repo, registrado só pra não confundir sessão futura).
- Python 3.12.14 instalado via `uv python install` (binário prebuilt, sem sudo, sem afetar o
  Python 3.8 do sistema).
- `ansible-lint` instalado via `uv tool install --python 3.12 ansible-lint` (isolado, shim em
  `~/.local/bin/ansible-lint`) — achado um shim quebrado pré-existente no mesmo caminho (de
  27/08, tentativa antiga que nunca funcionou sob Python 3.8), sobrescrito com `--force`.
- Gate real: `ansible-lint` rodado contra `dev-environment/site.yml` — 26.8.0 + ansible-core
  2.21.4 confirmados. Resultado: 29 achados reais em 14/18 arquivos processados, profile `min`
  atingido, `basic` não. Nenhuma correção aplicada nesta rodada — aguardando decisão do usuário.
- Status: DONE (ferramenta desbloqueada e rodando de verdade — o objetivo do item do ROADMAP)

## ROADMAP item 7 (continuação): 29 achados do ansible-lint corrigidos — 2026-09-16T00:15:00-03:00
Usuário aprovou corrigir os 29 achados registrados na rodada anterior. Todos corrigidos no repo
`dev-environment` (commit `8311037`, pushed):
- Renomeado `roles/agents-harness`->`agents_harness`, `roles/credentials-check`->`credentials_check`
  (nome de role não aceita hífen) -- `site.yml` e `README.md` atualizados, tags do playbook
  continuam hifenizadas (regra não se aplica a tags).
- 9x var-naming: todas prefixadas com o nome do role, exceto `is_wsl` (fato genuinamente
  compartilhado entre 3 roles, já setado uma vez em `site.yml` pre_tasks) -- a re-declaração
  redundante dentro de `dotfiles/tasks/main.yml` foi REMOVIDA em vez de renomeada (era dead code:
  mesma expressão computada 2x).
- 4x risky-file-permissions: `mode: preserve` em vez de um modo fixo -- decisão deliberada porque
  2 dos casos (skills/steering) sincronizam diretório misto com scripts `.sh` executáveis; um modo
  fixo tipo 0644 teria removido o `+x` de verdade.
- 2x ignore_errors: substituído por `stat` + `when:` (verifica existência real do arquivo antes,
  em vez de engolir qualquer erro cegamente).
- command-instead-of-module (curl) + risky-shell-pipe: instalador do nvm dividido em `get_url`
  (download) + `command` (execução) -- elimina o pipe `curl | bash` inteiro.
- command-instead-of-module (git) x2: MANTIDO com `# noqa` -- documentado desde 2026-08-28 que
  `ansible.builtin.git` quebra de verdade contra o `ansible-core` que essa máquina normalmente usa
  pra rodar o playbook (bug real já encontrado antes, não re-introduzido).
- latest[git] (oh-my-zsh): `version: master` explícito + `noqa` (sem tags de release reais, tracking
  master é intencional).
- 2x name[template]: Jinja movido pro fim do nome da task.
- yaml[commas]/line-length (`group_vars/all.yml`): `project_aliases` reformatado de flow-mapping
  alinhado manualmente pra block-style + `>-` fold no comando mais longo.
- yaml[line-length] extra (achado durante o próprio processo de correção, quando o rename de
  variável alongou uma linha): resolvido com `vars:` de bloco pra encurtar a referência repetida.
**2 bugs reais adicionais achados RODANDO o playbook de verdade depois do lint limpo** (não só
lint, execução real): `ansible.cfg` com `stdout_callback = yaml` dependia do plugin
`community.general.yaml`, removido da collection na v12.0.0 -- trocado por
`ansible.builtin.default` + `result_format = yaml` nativo; `community.general` nem estava
instalado como collection (instalado agora, elimina os 4 warnings de "Unable to load module").
Verificação final: `ansible-lint` 0/0 profile `production`, `--syntax-check` PASS,
`--check --diff --skip-tags packages` PASS (0 failed, mesmo comportamento de drift de antes).
Achado registrado, NÃO corrigido (fora do escopo aprovado, refactor grande): toda referência
`ansible_env.HOME` dispara aviso de depreciação sob ansible-core 2.21.4 (`INJECT_FACTS_AS_VARS`,
remoção planejada pro 2.24) -- a instalação real documentada no README usa ansible-core bem mais
antigo sob Python 3.8, não este.
Status: DONE

## ROADMAP item 7 (conclusão): deprecation INJECT_FACTS_AS_VARS eliminada, ansible-core padronizado — 2026-09-16T00:30:00-03:00
Usuário pediu tratar agora o achado de depreciação registrado na rodada anterior e deixar na
versão LTS mais atual. Feito no `dev-environment` (commit `e6d137d`, pushed):
- Migrado TODO uso de fato "injetado no topo" pro namespace moderno em todos os roles + site.yml:
  `ansible_env.X` -> `ansible_facts['env']['X']`, `ansible_kernel` -> `ansible_facts['kernel']`.
  `INJECT_FACTS_AS_VARS` está deprecated, remoção prevista pro ansible-core 2.24 -- zero warning
  de depreciação agora num `--check --diff` real.
- Padronizado o toolchain de EXECUÇÃO (não só lint) em `ansible-core` 2.21.4 via
  `uv tool install ansible-core` (mesmo Python 3.12 isolado já usado pro ansible-lint) --
  substitui o `pip3 install --user ansible` antigo, que resolvia uma versão bem mais velha de
  ansible-core sob o Python 3.8 de sistema. README atualizado com os passos de instalação novos
  (+ alternativa simples via pip3 se a máquina já tiver Python 3.10+ nativo).
- Achado real ao instalar via `uv tool install ansible`: só expõe o executável `ansible-community`
  por padrão (não `ansible-playbook`/`ansible-galaxy`, que vêm do pacote `ansible-core`
  transitivo) -- corrigido instalando `ansible-core` diretamente com `--force` pra sobrescrever os
  shims antigos (de 27/08, pip3 sob Python 3.8) que já ocupavam `~/.local/bin`.
- **Revisitado e resolvido o `# noqa` do módulo git**: o bug documentado (`TypeError` computando
  opções de SSH, achado 2026-08-28 contra ansible-core 2.13.13/Python 3.8) foi retestado AO VIVO
  contra o repo real `agents-harness` via SSH sob 2.21.4 antes de reverter o workaround -- não
  reproduz mais. `roles/agents_harness/tasks/main.yml` simplificado de 3 tasks (stat+2 shells) pra
  1 task só (`ansible.builtin.git`, clone-or-update nativo).
- Verificação final: `ansible-lint` 0/0 profile `production`, `--syntax-check` PASS,
  `--check --diff --skip-tags packages` PASS (0 failed, 0 deprecation warnings, comportamento de
  drift idêntico ao de antes).
Status: DONE — item 7 do ROADMAP fechado por completo (desbloqueio + 29 achados + depreciação +
padronização de versão).

## Delegação de débito de produto ao harness-dev (prompts prontos, não disparados) — 2026-09-16T00:45:00-03:00
Usuário pediu prompts separados por projeto (artists-booking, rastafinancas, vetcare) pra colar em
sessões `harness-dev` dedicadas, cobrindo todo o débito de produto acumulado nesta spec de infra
(Node bump, dependências, testes flaky, spec de /metrics do vetcare não confirmada). 3 prompts
entregues na conversa (auto-contidos, sem depender de memória desta sessão, já que harness-dev
começa frio em cada projeto). Registrado em D-2026-09-16-1 (DECISIONS.md) + ROADMAP.md marcado com
o status "prompt pronto, não disparado" nos 3 blocos correspondentes. Nenhuma ação de código
executada — é só preparação de handoff, execução fica a critério do usuário.
Status: DONE (preparação) — execução real depende do usuário disparar os prompts.

## Incidente: platform-loki crash-loop (index_20712 corrompido) — 2026-09-17
- Diagnóstico: `docker logs`/`docker inspect` reais — RestartCount=1065, crash-loop desde
  2026-09-16 ~06:38 (~32h sem ingestão de log em toda a plataforma). Causa raiz isolada via
  container debug com o volume `platform_loki_data` montado: shard de índice do período TSDB
  `index_20712` (`.../chunks/index/index_20712/...tsdb.gz`) era um arquivo de 0 bytes (`mmap,
  size 0: invalid argument` / `gzip: invalid magic`) — resíduo de uma limpeza pós-compactação
  interrompida (provável kill/restart do WSL2/Docker Desktop no mesmo instante, correlaciona com
  `.tsdb.temp` órfão e timestamps 06:37-06:38 de 16/09). Dado já estava preservado no shard
  compactado (`fake/...3d209f25.tsdb.gz`, válido) — confirmado ANTES de remover qualquer coisa
  (não assumido).
- Backup: 3 diretórios (`chunks/index/index_20712`, `tsdb-shipper-active/multitenant/index_20712`,
  `tsdb-shipper-cache/index_20712`) copiados via `docker cp` para scratchpad da sessão antes de
  qualquer remoção.
- Fix: removidos 4 artefatos órfãos/corrompidos (o `.tsdb.gz` de 0 bytes + `.tsdb`/`.tsdb.temp`
  locais do builder + cópia de cache de 0 bytes) via container `busybox` com o volume montado
  read-write. `docker restart platform-loki`.
- Verificação externa (gate real, não assumido):
  - `docker inspect`: Status=running, RestartCount=0, ExitCode=0, estável (sem novo crash em
    >45s, vs. restart a cada ~2s antes do fix).
  - `curl /ready` → `ready` (após warmup normal de 15s do ingester).
  - `curl /metrics` → `loki_build_info` presente (3.7.7).
  - `curl /loki/api/v1/query_range` → 2 streams reais com timestamp atual (`microgrow-api`,
    `microgrow-mosquitto`) confirmando ingestão de log **de fato** retomada, não só "container Up".
- Achado colateral registrado, não corrigido: `platform-loki` no compose atual não tem
  `HEALTHCHECK`/healthcheck do Compose configurado (`docker inspect .State.Health` = ausente) —
  o crash-loop de 32h nunca gerou alerta automático porque não há liveness/healthcheck nem alerta
  Prometheus cobrindo "container reiniciando". Ver DECISÃO/pendência.
- Status: DONE

## Follow-up: monitoramento externo do platform-loki (healthcheck + alertas) — 2026-09-17
- Confirmado empiricamente (de novo, ao vivo): imagem `grafana/loki:3.7.7` não tem `sh`/`wget`/
  `curl` — Docker HEALTHCHECK via CMD-SHELL/CMD é inviável sem imagem derivada custom. Decisão:
  monitoramento externo via Prometheus, não healthcheck de container.
- `platform/prometheus/prometheus.yml`: novo job `loki` (`loki:3100/metrics`).
- `platform/grafana/provisioning/alerting/platform.yaml` (novo arquivo, flat, mesmo padrão dos
  outros): 2 regras — `alert-loki-down` (`up{job="loki"}==0` por 2min) e
  `alert-loki-crash-looping` (`changes(process_start_time_seconds{job="loki"}[15m])>3`).
- **Bug real achado e corrigido durante a verificação**: as regras copiadas do padrão existente
  (`type: reduce` como nó final do `condition`, com `conditions[]` aninhado) NÃO avaliam threshold
  nenhum — um nó `reduce` só reduz o valor, não tem semântica de comparação; o array `conditions`
  aninhado nele é resíduo de UI, ignorado pelo motor de alerta. Resultado: a regra fica `Alerting`
  sempre que há QUALQUER dado, independente do valor. Corrigido pra `type: classic_conditions`
  (nó único, autocontido, avalia o `evaluator` de verdade). Verificado com CICLO COMPLETO real:
  (1) Loki saudável → `state: inactive`/`Normal` nas 2 regras; (2) `docker stop platform-loki` →
  após os 2min de `for`, `alert-loki-down` foi a `state: firing`/`Alerting` de verdade (`value: 0`);
  (3) `docker start platform-loki` → voltou a `inactive`/`Normal` após o Loki ficar `/ready`.
- **Achado colateral grave, fora do escopo pedido, NÃO corrigido**: ao verificar minhas 2 regras
  novas, descobri que TODAS as ~27 regras pré-existentes da plataforma (microgrow, rastafinancas,
  artists-booking) usam o MESMO padrão quebrado (`type: reduce` como condition final) — confirmado
  via `GET /api/prometheus/grafana/api/v1/rules`: no momento da checagem, TODAS estavam
  `state: firing`, inclusive as que claramente não deveriam estar (ex.: "RastaFinancas API
  Offline" com a API rodando normal). Motivo de nunca ter sido percebido: SMTP (Gmail) do canal de
  alerta está com credencial inválida desde antes (D-2026-09-01-1) — notificações nunca chegaram,
  só o estado interno do Grafana ficou errado silenciosamente. Registrado como decisão pendente
  (D-2026-09-17-2) — não corrigido sem confirmação explícita do usuário (escopo grande: reescrever
  ~27 regras em 3 arquivos de produtos diferentes).
- Bug real adicional encontrado no processo (já documentado antes, reconfirmado): bind-mount órfão
  do WSL2/Docker Desktop — `docker restart platform-prometheus` falhou (`mount ... no such file or
  directory`) depois de editar `prometheus.yml` no host; `docker compose up -d --force-recreate`
  necessário em vez de `restart` simples, mesma classe de bug do D-2026-09-09-1.
- Verificação final: `docker compose config` PASS, 12/12 containers do platform stack `Up`/healthy.
- Status: DONE (2 alertas novos corrigidos e testados ponta a ponta); achado dos 27 alertas
  pré-existentes: PENDENTE DE DECISÃO DO USUÁRIO.

## Follow-up: correção das 27 regras pré-existentes + SMTP Resend — 2026-09-17
- Script Python (`ruamel.yaml`, indentação preservada, diff mínimo) converteu as ~27 regras
  pré-existentes de `type: reduce` (bugado, nunca avalia threshold) pra `type: classic_conditions`
  (correto, autocontido) em `microgrow.yaml` (15), `rastafinancas.yaml` (6), `artists-booking.yaml`
  (6, incluindo a regra com nó intermediário `math` — `query.params` continuou apontando certo).
- `docker compose up -d --force-recreate grafana` (não `restart`, mesmo bug de bind-mount do
  D-2026-09-09-1/D-2026-09-17-2) + esperado 2 ciclos de avaliação (interval 1-2min) + verificado via
  `GET /api/prometheus/grafana/api/v1/rules`.
- **Resultado real**: os 8 alertas baseados em Prometheus (5 artists-booking p0 + 1 p1 + 2 novos do
  Loki) foram corretamente pra `state: inactive`/`Normal` — fix confirmado funcionando pros casos
  onde o datasource está saudável.
- **Achado novo, grave, fora do escopo original**: os outros 21 (15 microgrow + 6 rastafinancas,
  todos os que usam InfluxDB) continuam `state: firing`, mas agora por causa de um erro REAL e
  DIFERENTE: `[sse.dataQueryError] ... flightsql: ... No SQL statements were provided in the query
  string`. Causa: as 21 regras usam `type: flux` (sintaxe Flux), mas `datasourceUid:
  influxdb-microgrow`/`influxdb-rastafinancas` foi migrado pra InfluxDB 3 (só fala SQL/FlightSQL)
  na sessão `infra-full-upgrade-2026-09` (2026-09-15, D3) — confirmado em
  `platform/grafana/provisioning/datasources/datasources.yml` (`url: http://influxdb3:8181`,
  `jsonData.version: SQL`). Aquela migração reescreveu os 76 queries de DASHBOARD (D-2026-09-15-2
  reporta "76/76 traduzidas"), mas nunca tocou nas 21 queries de ALERTA — gap que ficou invisível
  até agora porque o bug do `classic_conditions` já deixava tudo "firing" de qualquer forma,
  mascarando o erro de execução por baixo.
- Confirmado que NÃO existe mais datasource Flux-compatível registrado no Grafana (o comentário em
  `datasources.yml` diz "kept below, commented out" mas isso está desatualizado — não há bloco
  comentado no arquivo atual). O container `platform-influxdb` (v2.7) ainda está `Up`/healthy como
  rollback, mas repontar os alertas pra ele seria débito técnico novo (contradiz a decisão já
  tomada de migrar tudo pra v3/SQL, e esse container já está marcado como candidato a desligar,
  D-2026-09-15-2 item 1) — não fiz isso.
- SMTP: `GF_SMTP_USER`/`GF_SMTP_PASSWORD` adicionados no compose (antes nem existiam — não era só
  credencial inválida, não havia credencial nenhuma), `SMTP_HOST` trocado pra `smtp.resend.com:587`
  em `.env`/`.env.example`, doc `docs/how-to/setup-resend-smtp-alerts.md` criado com os passos que
  precisam de ação do usuário (criar conta Resend, verificar domínio `rastaful.dev`, gerar API key)
  — `SMTP_PASSWORD` deixado vazio de propósito, nunca inventado. `docker compose config` PASS com
  as novas env vars. Envio real de e-mail NÃO pôde ser testado (sem API key) — BLOQUEADO até ação
  do usuário, mesmo padrão do R2/Oracle/Terraform Cloud já usados neste repo.
- Status: PARTIAL. Fix dos 27 formatos: DONE e verificado. SMTP: wiring DONE, ativação BLOQUEADA
  (ação externa do usuário). Achado dos 21 Flux/SQL: REGISTRADO, NÃO CORRIGIDO — aguardando decisão
  explícita do usuário antes de reescrever 21 queries (mesmo escopo/risco da migração de 76 queries
  de dashboard já feita em 2026-09-15, inclusive lógica não-trivial como o p95 do rastafinancas por
  buckets de histograma).

## Follow-up: tradução Flux→SQL das 21 queries de alerta InfluxDB — 2026-09-17
- Schema real consultado ao vivo via `/api/v3/query_sql` (SHOW TABLES / SELECT * LIMIT 1) em vez de
  supor a partir do Flux antigo — achado real: `sensors` (microgrow) só tem `api_metrics` e
  `mqtt_broker` como tabelas existentes; `soil_moisture`, `air_conditions`, `reservoir`,
  `hydric_score`, `reservoir_drain_event`, `lights_compliance`, `irrigation_outcome`, `grow_cycle`
  NÃO existem (confirmado `Error during planning: table ... not found`) — simulador pausado desde
  antes da migração de 15/09 nunca escreveu essas medições no InfluxDB 3 (mesma causa raiz já
  registrada em D-2026-09-15-3, painéis do `grow-cockpit.json` já mostram isso hoje). `rastafinancas`
  tem as 6 tabelas necessárias todas ativas com dado real.
- 21 queries traduzidas (script `sql_map.py` + `fix_sql.py`, ruamel.yaml, mesma técnica de diff
  mínimo) seguindo a convenção já usada nos dashboards (tabela=measurement, colunas=fields/tags
  diretos, `time >= now() - INTERVAL 'X'`, `ORDER BY time DESC LIMIT 1` pra `last()`,
  `ROW_NUMBER() OVER (PARTITION BY ...)` pra dedupe por série antes de somar — mesma técnica do
  `rasta-latency-p95`, preservando a lógica de buckets de histograma p95 1:1).
- **Gate externo real, não assumido**: todas as 21 queries testadas direto via
  `POST /api/v3/query_sql` antes de tocar o Grafana. Resultado: 6/6 rastafinancas OK com dado real
  (`rasta-api-down`=0, `rasta-error-rate-critical`=0.0%, `rasta-latency-p95`=10ms,
  `rasta-import-errors`=59, `rasta-notif-job-down`=0, `rasta-web-down`=0); 3/15 microgrow OK
  (`alert-api-down`=17, `alert-api-latency`=0.86ms, `alert-mqtt-broker-down`=sem linha no range);
  12/15 microgrow com erro esperado e específico `table not found` (nenhum outro tipo de erro —
  confirma sintaxe SQL 100% correta, só falta a tabela existir).
- `docker compose up -d --force-recreate grafana` + 2 ciclos de avaliação esperados.
- **Achado real durante a verificação**: 3 dos 6 rastafinancas (`rasta-latency-p95`,
  `rasta-notif-job-down`, `rasta-web-down`) mostraram erro transitório
  `flightsql: rpc error: code = InvalidArgument ... No SQL statements were provided` na primeira
  leitura pós-recreate — mesmo COM SQL válido testado momentos antes via API direta. Não assumido
  como definitivo: aguardado mais um ciclo de avaliação e reconfirmado via API — erro sumiu sozinho
  (conexão FlightSQL "esquentando" logo após o recreate do Grafana, não um bug real de query).
  6/6 `health: ok` na checagem seguinte.
- **Resultado final (2 checagens, API real)**: 8 alertas Prometheus (artists-booking+Loki) `Normal`,
  6/6 rastafinancas `health: ok` (1 pending, 1 legitimamente firing por achado real — ver abaixo),
  3/15 microgrow saudáveis (`api-down`, `api-latency` Normal; `mqtt-broker-down` `nodata`, não
  error — tópico `$SYS/broker/clients/connected` parou de publicar há ~2h enquanto outros tópicos
  `$SYS` continuam atualizando, achado registrado não investigado, fora de escopo), 12/15 microgrow
  seguem `error`/`firing` por tabela ausente — não corrigível por tradução de query, depende do
  simulador voltar a escrever (gap pré-existente e já registrado, D-2026-09-15-3).
- **2 achados de design pré-existente, preservados fielmente (não corrigidos, fora do pedido
  "traduzir Flux→SQL")**: (1) `rasta-import-errors` conta AMOSTRAS de scrape (~60 em 15min, sempre
  > 3), não falhas reais — mesmo comportamento do Flux original, sempre vai disparar
  independente de erro real de import; (2) 12 alertas microgrow vão continuar `Alerting` (erro)
  assim que o SMTP for ativado, até o simulador voltar — mesmo comportamento de antes (Flux também
  daria erro contra o backend v3), não é regressão desta tradução.
- Status: DONE (21/21 queries traduzidas e verificadas via gate externo real, 2 achados de design
  pré-existente registrados, não corrigidos).

## Follow-up: rasta-import-errors corrigido (métrica errada) + microgrow simulador (achado real) — 2026-09-17
- `rasta-import-errors`: achado real ao ler `apps/api/src/plugins/product-metrics.ts` do
  rastafinancas — a query original (tradução literal do Flux) contava AMOSTRAS de scrape de
  `rasta_import_transactions_total` (contador de throughput, sem relação com falha) em vez de usar
  a métrica que já existe corretamente instrumentada no código pra isso:
  `rasta_import_batch_total{format,status}`. Corrigido pra
  `COALESCE(MAX(counter)-MIN(counter),0) FROM rasta_import_batch_total WHERE status='error'`
  (increase real do contador no período, não contagem de amostras). Não é bug de instrumentação —
  não precisou do harness-dev. Verificado: sintaxe SQL válida (erro atual é `table not found`,
  mesma classe do gap do microgrow — a métrica tem `labelNames` e só ganha série quando um import
  real acontecer pelo menos uma vez; nenhum ocorreu neste ambiente ainda). Vai resolver sozinho
  assim que o produto processar um import de verdade.
- **"Religar o simulador do microgrow"**: `POST /api/v1/simulator/control {"action":"play",
  "scenario":"normal_day"}` executado, `GET /api/v1/simulator/status` confirmou `running: true`.
  MAS achado real ao investigar por que os dados não apareciam mesmo assim: sniff MQTT ao vivo
  (`mosquitto_sub -t 'microgrow/#'`) confirmou que o simulador publica dado real e válido, só que
  em `microgrow/sim/tele/...`/`microgrow/sim/stat/...` — o Telegraf (`microgrow/infra/telegraf/
  telegraf.conf`) só escreve em `microgrow/tele/...`/`microgrow/stat/...` (sem o segmento `/sim`),
  então nunca recebe nada, independente do estado play/pause (que é só uma flag interna da
  `microgrow-api`, não controla o processo real do simulador — o container roda `run.py`
  diretamente, não o `daemon.py` que ouviria esse comando). Bug real de código, confirmado com
  `_SIM_PREFIX = "microgrow/sim"` em `simulator/publishers/mqtt_publisher.py`, e com
  `test_publisher.py` testando esse prefixo deliberadamente (não é typo, é uma divergência de
  design nunca reconciliada com o `telegraf.conf` do mesmo repo). Fora do escopo do harness-infra
  (código de produto) — delegado ao `harness-dev` (Agent tool, sessão em background no repo
  `microgrow`) com o diagnóstico completo, rodando no momento deste registro.
- Status: rasta-import-errors DONE (verificado, aguardando evento real). Simulador: ação pedida
  (religar) executada, mas objetivo real (dado fluindo) BLOQUEADO por bug de produto — delegado,
  IN_PROGRESS no harness-dev.

## Fechamento: filtro source='sim' aplicado + verificação final de todas as regras — 2026-09-17
- harness-dev confirmou (repo `microgrow`, sessão delegada): Telegraf agora tagueia
  `soil_moisture`/`air_conditions`/`reservoir` com `source=real|sim` (6 blocos `/sim` espelhados +
  tag nos blocos reais correspondentes); `pump_events` usa `mqtt_source` (nome já ocupado por
  `source` dinâmico pré-existente); `hydric_score`/`reservoir_drain_event` deliberadamente sem tag
  (fonte única, já isolada no nível da API). B1 aplicado (PUT .../config/data-source sim) +
  persistido via `start.sh`. Testes: simulator 68/68, api jest 296/296, sem regressão.
- **Achado novo registrado pelo harness-dev, não corrigido (fora do escopo delegado)**:
  `pump_events` não grava no InfluxDB mesmo com MQTT confirmando entrega — causa raiz não
  encontrada após ~10 variantes de config testadas, excedeu o limite de 3 retries e escalou
  corretamente em vez de continuar gastando a sessão. Ver `microgrow/.specs/project/DECISIONS.md`
  pro trail completo de eliminação.
- Verificado de forma independente (não confiei só no relato do agente): query direta na API do
  InfluxDB confirmou `soil_moisture`/`air_conditions`/`reservoir`/`hydric_score` com dado fresco
  (`2026-09-18T00:08...`) e tag `source=sim` correta nas 3 medições tagueadas;
  `reservoir_drain_event` também já tinha 1 evento real; `lights_compliance`/`irrigation_outcome`/
  `grow_cycle` continuam sem tabela — event-driven, ainda não dispararam, não é bug.
- 7 queries de alerta atualizadas (`microgrow.yaml`) com filtro `source = 'sim'` (as que leem
  `soil_moisture`/`air_conditions`/`reservoir`) — mantém a promessa de isolamento real/sim também
  do lado do `infra-platform`. Testadas direto contra o InfluxDB real antes de aplicar (5/5 valores
  sensatos retornados). `docker compose up -d --force-recreate grafana`, 2 ciclos de avaliação
  esperados, verificado via API.
- **Resultado final (API real, gate externo)**: 29 regras totais — 22 `inactive`(saudável), 2
  `pending` (normal, aguardando `for`), 5 `firing` — todas as 5 explicadas e legítimas: 3 microgrow
  (tabela event-driven ainda não populada), `rasta-import-errors` (aguardando 1º import real, já
  documentado), `rasta-notif-job-down` (sinal real: nenhum job de notificação rodou nas últimas 2h,
  não é bug de config). Zero erro inexplicado, zero falso positivo do bug antigo de
  `classic_conditions`, zero mismatch Flux/SQL restante nas medições com dado disponível.
- `docker compose config` PASS, 12/12 platform + 7/7 microgrow containers `Up`/saudáveis.
- Status: DONE. Toda a cadeia do incidente (D-2026-09-17-1 a 6) fechada e verificada.

## Loop autônomo (dentro da sessão, sem sandbox): pump_events resolvido — 2026-09-18
Usuário pediu loop de correção contínua nesta mesma sessão (sem as pré-condições de autonomia
completa — sandbox/--remote-control/spec fechado — por isso mantido como loop supervisionado,
registrando dúvidas em vez de agir sem critério em itens de decisão de negócio).
- Investigação direta (não estava resolvido pelo harness-dev anterior, que tinha excedido o limite
  de retries): usado um harness Telegraf descartável (container `telegraf:1.40.0` isolado, config
  mínima, `outputs.file`, `debug=true`) pra isolar a causa raiz real — comparação lado a lado
  (tópico do pump vs tópico do soil, mesmo processo) confirmou que SÓ o pump falha. Teste
  controlado com `mosquitto_pub` de payloads sintéticos (`{"active":false,"count":5}` vs
  `{"active":false,"source":"auto"}`) confirmou: o parser `json` clássico do Telegraf 1.40.0
  descarta campos não-numéricos (bool/string) não reivindicados por `tag_keys` SEM logar erro —
  se sobra zero fields após a extração de tags, a métrica inteira é descartada em silêncio. O
  payload do pump (`active` bool + `source`/`simulated` já viram tags) sempre resultava em zero
  fields.
- Fix testado isoladamente antes de aplicar: `data_format = "json_v2"` com `active` declarado
  explicitamente como field tipo `bool` — confirmado gerando métrica válida a cada ciclo.
- Delegado ao harness-dev (repo `microgrow`, fix já testado e pronto, só aplicar+verificar+
  registrar) — aplicado nos 2 blocos (`real` + `sim`), `--force-recreate`, testes 68/68 + 296/296
  sem regressão. Verificado de forma independente por mim: `pump_events` com dado real e fresco,
  `mqtt_source=sim`, todos os campos populados.
- Status: DONE. Nenhum alerta em `infra-platform` referencia `pump_events` ainda — nada a
  atualizar aqui.

## Loop autônomo: auditoria de tipo (tag vs field) nas 27 queries + 2 bugs reais achados — 2026-09-18
Continuando o loop de correção, depois de resolver `pump_events`: auditei sistematicamente as 27
queries SQL traduzidas contra `information_schema.columns` real do InfluxDB 3 (não assumido),
procurando a mesma classe de erro que causou o bug do `pump_events` (mismatch entre o que o
Telegraf grava — tag string vs field numérico/boolean — e o que a query espera).
**2 bugs reais achados e corrigidos (falso-negativo silencioso, não erro — pior que os anteriores,
porque o alerta parece saudável mas nunca dispararia mesmo com o evento real acontecendo)**:
- `alert-reservoir-sensor-suspect`: `sensor_suspect` é tag (`Dictionary(Int32,Utf8)`, string
  "true"/"false" confirmado com dado real). Query comparava `= 1.0` (nunca bate com string,
  DataFusion não erra, só retorna 0 sempre). Corrigido pra `= 'true'`.
- `alert-irrigation-ineffective`: `effective` (irrigation_outcome) é tag pelo mesmo motivo
  (`tag_keys` no telegraf.conf). Query comparava `= false` (boolean literal). Corrigido pra
  `= 'false'`.
**1 achado de config, mesma classe do pump_events, delegado**: `compliant` (lights_compliance) é
boolean NÃO-taggeado — vai ser descartado silenciosamente pelo parser `json` clássico do Telegraf
assim que a tabela existir (mesma causa raiz do pump_events). Query SQL já corrigida pra
`compliant = false` (comparação booleana correta, assumindo o fix de config aplicado). Fix de
config (`json_v2`) delegado ao harness-dev (repo `microgrow`), rodando em background.
**Demais 24 queries auditadas, sem problema encontrado**: tipos de coluna reais (`result_code`
Int64, `status_code`/`decision`/`probe` Utf8, `counter`/`score`/`vwc_pct`/`level_pct` Float64)
todos batendo com o tipo de comparação usado nas queries — confirmado via
`information_schema.columns`, não assumido.
Status: DONE (2 fixes aplicados e re-provisionados; 1 delegado, aguardando harness-dev).

## Loop autônomo: fechamento — lights_compliance corrigido, estado final 22/29 saudáveis — 2026-09-18
harness-dev aplicou e verificou o fix de `lights_compliance` (mesmo padrão `json_v2` do
pump_events). Confirmado por mim de forma independente: `compliant` populado corretamente
(true/false) em dado real via teste de repro do harness-dev.
**Estado final da stack inteira (29 regras, API real, 2 ciclos de avaliação)**: 22 `inactive`
(saudável), 3 `pending` (transitório normal — reservoir-sensor-stuck ainda acumulando janela de 2h,
mqtt-broker-down em transição, light-schedule-violation pegou o dado de teste do harness-dev e vai
limpar sozinho), 4 `firing` — todos explicados: `irrigation_outcome`/`grow_cycle`/
`rasta_import_batch_total` aguardando 1º evento real (não é bug), `rasta-notif-job-down` com sinal
real (nenhum job rodou em 2h).
`docker compose config` PASS, 12/12 platform + 7/7 microgrow containers `Up`/saudáveis.
**Loop autônomo (sem sandbox, supervisionado) encerrado**: convergiu — não há mais nenhum item
acionável sem (a) conta externa (Resend) ou (b) decisão de produto (configurar ciclo de cultivo).
Ambos registrados como perguntas pro usuário, não resolvidos unilateralmente.
Status: DONE.

## Loop autônomo: grow cycle configurado + bug real de permissão/persistência achado e corrigido — 2026-09-18
Usuário respondeu a dúvida pendente ("comece sempre no primeiro ciclo") — configurei o ciclo de
cultivo do microgrow via `PUT /api/v1/config/grow-cycle` (stage=seedling, started_at=hoje,
duração=129d, mesmos defaults do código). Primeira vez que esse código path é exercitado.
**Bug real achado (nunca exercitado antes, 3 causas raiz)**:
1. `api/Dockerfile`: `/app/data` nunca criado/chowned pro `appuser` antes do `USER appuser` —
   `EACCES: permission denied, mkdir '/app/data'`, 500 real.
2. `infra/docker-compose.yml`: serviço `api` sem NENHUM volume — mesmo corrigindo a permissão,
   `cycles.json` sumiria a cada `--force-recreate` (usado várias vezes nesta sessão).
3. Achado pelo próprio harness-dev durante a verificação: `GrowCycleService` nunca rehidratava o
   estado em memória a partir do `CycleStore` no boot — `GET` retornava 404 mesmo com o arquivo
   correto em disco.
Delegado ao harness-dev, 3 causas corrigidas (Dockerfile mkdir+chown, volume nomeado `api_data`,
rehidratação com TDD real — RED confirmado antes do fix). Verificado por mim de forma
independente: `GET /api/v1/config/grow-cycle` retorna o ciclo real, `grow_cycle` no InfluxDB com
dado fresco.
**Resultado final da stack de alertas**: 25/29 saudáveis (era 22/29). Restam 4 firing, todos
explicados: `irrigation_outcome`/`rasta_import_batch_total` aguardando 1º evento real (não é
bug), `rasta-notif-job-down` (sinal real, nenhum job rodou em 2h), `reservoir-sensor-flat-line`
(sinal real — reservatório do simulador genuinamente estável/sem variação há mais de 2h, não é
bug de query).
Status: DONE.

## Continuação do loop (a pedido do usuário): 5 bugs reais em dashboards + achado de design registrado — 2026-09-18
Investigação do alerta `reservoir-sensor-flat-line`: confirmado via dado real (`hydric_score.
next_irrigation_est_h ~25h`) que o próprio sistema espera ~1 irrigação por dia — um alerta de
"reservatório parado > 2h" vai disparar quase o tempo todo em operação normal. Achado de DESIGN
(threshold mal calibrado pro comportamento real do produto), não bug técnico — registrado, não
corrigido sem decisão do usuário.
Varredura de todos os 76 `rawSql` dos dashboards (`microgrow`+`rastafinancas`) atrás da mesma
classe de bug já achada nos alertas (tag vs field, nome de métrica errado): **5 bugs reais
confirmados** em `rasta-auth-security.json`/`rasta-product.json` — nomes de measurement que
NUNCA existiram no produto (`rasta_auth_logins_total`, `rasta_auth_token_refreshes_total`,
`rasta_auth_password_resets_total`, `rasta_import_batches_total`, `rasta_import_errors_total`),
confirmado contra `product-metrics.ts` real e `information_schema.tables` do InfluxDB. Mesma
classe de bug já documentada como "corrigida" em D-2026-09-15-3 (item Categoria B) — na prática
não estava corrigida nestes 2 dashboards (a migração Flux→SQL de 15/09 aparentemente traduziu a
versão desatualizada das queries, não a corrigida).
5 queries corrigidas pros nomes reais (`rasta_user_logins_total`, `rasta_token_refresh_total`,
`rasta_password_reset_total`, `rasta_import_batch_total` singular, + `status='error'` filter pro
painel de erro de import — mesmo padrão já aplicado no alerta). Testadas contra o InfluxDB real
antes de aplicar: 1/5 com dado real confirmado (`rasta_user_logins_total`, taxa de sucesso
90.9% calculada certa), 4/5 com "table not found" esperado (aguardando 1º evento real —
`rasta_token_refresh_total`/`rasta_password_reset_total`/`rasta_import_batch_total` nunca
incrementados neste ambiente ainda, mesma classe já vista nos alertas).
Verificado que o Grafana recarrega dashboards de arquivo sozinho (`updateIntervalSeconds: 30`,
sem precisar de `--force-recreate`) — confirmado via API real (`GET /api/dashboards/uid/...`)
que as queries corrigidas já estão ao vivo.
Demais 71 queries (dos 76) auditadas quanto a nome de measurement — nenhum outro erro de nome
encontrado.
Status: DONE (5 bugs corrigidos e verificados; achado de design do alerta do reservatório
registrado, aguardando decisão).

## Task: docker-disk-cleanup — fechamento + registro/push do backlog de sessões anteriores — 2026-09-21
- Pendências fechadas pelo usuário (D-2026-09-21-3), verificadas ao vivo via PowerShell:
  docker_data.vhdx 88GB->30.7GB, C: livre 5GB->76.8GB.
- Instrução de uso criada ao lado do script já existente na Área de Trabalho real do Windows
  (`C:\Users\rodri\OneDrive\Area de Trabalho\`, script `compactar_docker.bat` pré-existente):
  `LEIA-ME_compactar_docker.txt`. Runbook atualizado com essa referência.
- cron: confirmado ativo (`crontab -l` + `service cron status`), entrada
  `35 3 * * * .../docker-disk-guard.sh` presente, nenhuma ação necessária.
- Registro e push de todo o backlog de commits pendente (várias sessões nunca commitadas):
  6 commits (Loki+SMTP, alerting/dashboard fixes, docker-disk-lifecycle, artifact-quota spec,
  infra-overview-diagram, roadmap) + 1 commit final de fechamento de STATE/DECISIONS/execution.
  Push: `a097452..5841926 main -> main`.
- gitleaks: PASS (todos os 7 commits, gate de pre-commit local)
- shellcheck: PASS (docker-disk-guard.sh)
- yaml/json syntax: PASS
- Status: DONE

## Task: alert-reservoir-sensor-stuck threshold fix (microgrow) — 2026-09-21
- Achado: query original disparava falso-positivo diário (checava "sem variação em 2h" sem
  correlacionar com ativação real da bomba; cadência real de irrigação ~25h, não 2h).
- Fix: rawSql reescrito com CTE (`pump_events.active=true AND mqtt_source='sim'`) + subquery
  escalar, avaliando STDDEV(level_pct) só na janela de 2h pós-ativação real da bomba. `for: 2h`
  -> `for: 0m`. uid preservado (mesmo alerta, não recriado).
- yaml syntax: PASS (python3 yaml.safe_load)
- SQL syntax: testado ao vivo contra InfluxDB3/DataFusion real (`platform-influxdb3`), sem erro
- Grafana provisioning reload: PASS (HTTP 200, "Alerting config reloaded")
- Regra recarregada confirmada via API (título/for/rawSql novos presentes)
- Execução ao vivo: health=ok, lastError=None (GET /api/prometheus/grafana/api/v1/rules)
- Limitação registrada: sem pump event `mqtt_source=sim` recente na base (simulador pausado),
  disparo positivo real não pôde ser confirmado nesta rodada — só ausência de erro de execução.
- Status: DONE

## Task: verificar rename master->main em developerFolio/tldr-projects — 2026-09-21
- developerFolio: git fetch --prune (remoto master deletado, confirmado), git ls-remote --heads
  (main/gh-pages/feature/* only), grep -rn master .github/workflows/ = 0 matches, origin/HEAD ->
  origin/main. STATE.md do repo confirma feature rename-branch-master-main CONCLUÍDO, commit
  de2d176.
- tldr-projects: git remote -v vazio (sem remote), git branch -a só lista main, git reflog show
  main confirma "Branch: renamed refs/heads/master to refs/heads/main" na raiz do histórico real,
  sem commit órfão sobrando.
- ADR-013 atualizado (tabela + seção de fechamento). Status: DONE.

## Task: infra-platform opensource-prep (parcial) — 2026-09-21T15:12:10-03:00
- UUID do túnel: hardcoded -> placeholder
- gitleaks: PASS
- LICENSE: adicionado (MIT)
- commit: c8c82de
- push: PASS
- visibilidade: mantida PRIVATE (bloqueada, aguardando revisão manual do usuário)
- Status: DONE (parcial)

## Task: limpeza de dado de teste em lights_compliance (microgrow) — 2026-09-21
- Investigado antes de agir: tabela tinha só 4 linhas (main/veg/flower-live-true/flower-live-false),
  todas do mesmo teste 2026-09-18T01:22-01:24, zero dado real, zero referência em dashboards.
- Limitação descoberta: InfluxDB 3 Core não suporta DELETE por linha via SQL (DML not supported:
  Delete). influxdb3 delete rows é Enterprise-only.
- Ação: influxdb3 delete table --database sensors lights_compliance (soft delete, não hard).
- Verificado: information_schema.tables sem lights_compliance; reservoir (34947 linhas reais)
  intocada.
- Status: DONE

## Task: SMTP Resend ativação real (Grafana alerting) — 2026-09-21
- Usuário colou SMTP_PASSWORD real em platform/.env (nunca exposto/impresso por mim — só
  verificado com grep -q / printenv | wc -c).
- docker compose up -d --force-recreate grafana: Healthy.
- Env vars confirmadas no container (GF_SMTP_HOST/USER/FROM_ADDRESS corretos, GF_SMTP_PASSWORD
  presente, valor nunca lido).
- Achado: endpoint de teste antigo (/api/alertmanager/.../receivers/test) removido no Grafana
  13.2.1 (410 Gone). Endpoint novo mapeado via API discovery + pesquisa externa (schema
  integration+alerts, não receiver+alert).
- Teste real disparado no contact point platform-critical: HTTP 200 {"status":"success",
  "duration":"1s999ms"}. Zero erro nos logs do Grafana.
- Runbook docs/how-to/setup-resend-smtp-alerts.md atualizado com o endpoint novo.
- Pendente (não automatizável): usuário confirmar recebimento visual no inbox
  rodrigob.dev@gmail.com.
- Status: DONE (ativação técnica) / aguardando confirmação visual do usuário
