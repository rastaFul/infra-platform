# SPEC: Promtail — PM2 logs → Docker socket (logs de app não chegam mais no Loki)

## Status: DRAFT — aguardando decisão do usuário (D1/D2/D3 abaixo)
## Created: 2026-08-29
## Owner: rodrigo

---

## Contexto

Item do roadmap (`ROADMAP.md` Batch 3) que ficou pendente desde antes da migração PM2→Docker (`features/local-boot-persistence/spec.md`, DONE 2026-08-29). Agora que os 5 componentes (rastafinancas, microgrow, vetcare, artists-booking, tunnel) rodam via Docker Compose, os Promtails que ainda esperam arquivo de log do PM2 (`~/.pm2/logs/*.log`) não recebem mais nenhuma linha nova — silenciosamente, sem erro.

Investigação real feita nesta sessão (não assumida — lido cada compose/config):

### rastafinancas
- `infrastructure/observability/docker-compose.yml`: serviços `rasta-telegraf` e `rasta-promtail`.
- **Achado real, sem relação com a migração de hoje**: os dois containers estão `Exited (0) 3 weeks ago` — pararam há 3 semanas (antes até do incidente do tunnel), não voltaram porque `restart: unless-stopped` respeita parada manual (comportamento correto do Docker, não é bug). Ou seja, **logs e métricas de produto do rastafinancas não estão sendo coletados há 3 semanas**, gap maior do que só "Promtail lê path errado".
- `promtail/config.yml`: 4 jobs, todos `static_configs` com `__path__: /pm2logs/rastafinancas-*.log` (arquivo, monta `/home/rodrigo/.pm2/logs:/pm2logs:ro`). Sem nenhum job Docker.
- `telegraf/telegraf.conf`: já usa `http://host.docker.internal:3001/metrics` e `/api/health` — **isso continua funcionando** (rastafinancas-api container publica em `127.0.0.1:3001`, mesmo padrão validado no incidente do tunnel), não precisa mudar. Só precisa o container voltar a rodar.
- Comentário do compose file (`Requires platform_net: cd ~/services/platform`) é doc velha (path pré-consolidação, ADR 010) — `platform_net` em si está correto (nome bate), só o comentário está desatualizado.

### microgrow
- `infra/docker-compose.yml`, serviço `promtail` — **está rodando** (`microgrow-promtail`, Up), já tem um job `docker_sd_configs` funcional (`unix:///var/run/docker.sock`, filtro por nome de container, pipeline `docker: {}`) cobrindo `microgrow-mosquitto`, `microgrow-influxdb`, `microgrow-grafana`, `microgrow-telegraf`.
- **Mas não cobre os containers de app** (`microgrow-api`, `microgrow-webapp`, `microgrow-webapp-sim`, `microgrow-simulator`) — esses ainda só têm jobs `static_configs` apontando pra `/pm2-logs/microgrow-*.log`, que não recebe mais nada desde a migração de 2026-08-28.
- Prova de conceito já existe e funciona neste mesmo arquivo — é só estender o filtro pros 4 containers de app.

### vetcare / artists-booking
- **Nunca tiveram Promtail** — não é regressão desta migração, é ausência de sempre. Fora do escopo original deste item do roadmap (que era especificamente "PM2 logs → Docker socket"), mas fica registrado como gap relacionado — ver D2.

## Causa raiz

Duas causas distintas, não uma só:
1. **rastafinancas**: containers de observabilidade parados há 3 semanas (operacional, não relacionado a código/config) — precisa só restart, mas fora do controle do agente sem confirmação (podem ter sido parados de propósito).
2. **microgrow**: config existe e funciona pro padrão certo (`docker_sd_configs`), só não foi estendida pros containers de app migrados ontem.

## Decisões necessárias antes de executar

- **D1**: Restartar `rasta-telegraf`/`rasta-promtail` (rastafinancas) — confirma que não foram parados de propósito por algum motivo que eu não tenho contexto (ex: economia de recursos, debug de outra coisa)?
- **D2**: Escopo — só rastafinancas + microgrow (restaura o que já existia, sem PM2), ou também criar Promtail do zero pra vetcare e artists-booking (expande cobertura, escopo maior, projeto sem histórico de log centralizado antes)? Recomendação: fazer só rastafinancas+microgrow agora (fecha o item do roadmap como estava definido), tratar vetcare/artists-booking como spec própria depois se você quiser.
- **D3**: Convenção de labels — replicar exatamente o padrão do `docker_sd_configs` do microgrow (que já funciona) nos dois lugares, ou padronizar algo novo? Recomendação: replicar o que já funciona, não inventar padrão novo pra 2 containers.

## Plano (após D1/D2/D3)

1. **rastafinancas**: reescrever `promtail/config.yml` — trocar os 4 jobs `static_configs`/arquivo por 1 job `docker_sd_configs` (mesmo padrão do microgrow) filtrando `rastafinancas-api`, `rastafinancas-web`. Remover o mount `/home/rodrigo/.pm2/logs:/pm2logs:ro` do compose (não serve mais pra nada). Restart de `rasta-telegraf` + `rasta-promtail` (D1).
2. **microgrow**: estender o job `docker_sd_configs` existente em `promtail-config.yaml` pra incluir `microgrow-api`, `microgrow-webapp`, `microgrow-webapp-sim`, `microgrow-simulator`. Remover os 4 jobs `static_configs`/arquivo (mortos) e o mount `/home/rodrigo/.pm2/logs:/pm2-logs:ro`.
3. Corrigir os comentários desatualizados (`~/services/platform` → `infra-platform/platform/`) nos dois compose files, já que estou mexendo neles.
4. Validar com gate externo real (não self-reportado):
   - `promtail -config.file=... -check-syntax` (sintaxe, PASS/FAIL)
   - `docker compose config` (PASS/FAIL)
   - `docker compose up -d` + esperar containers `Up`
   - Query real na API do Loki (`http://localhost:3100/loki/api/v1/query_range` ou via Grafana) confirmando linhas novas dos containers de app aparecendo, não só o container `Up` — gerar uma requisição real pro rastafinancas-api/microgrow-api primeiro pra garantir que existe log novo pra achar.

## Done Criteria
- `rasta-telegraf` e `rasta-promtail`: `Up` (não mais `Exited`).
- Promtail (rastafinancas e microgrow) scraping via `docker_sd_configs`, zero referência a `/pm2*logs` nos compose files.
- Gate: query real no Loki retorna linhas recentes (`< 2 min`) com label `container` ou `service` batendo pra `rastafinancas-api`, `rastafinancas-web`, `microgrow-api`, `microgrow-webapp`, `microgrow-webapp-sim`, `microgrow-simulator` — não só "container Up", log de verdade chegando.
- `docker compose config` PASS nos 2 projetos.
