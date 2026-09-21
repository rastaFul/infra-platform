# SPEC: Docker Disk Lifecycle

## Status: DONE (2026-09-21) — todas as 6 tasks concluídas e verificadas
## Created: 2026-09-21
## Owner: rodrigo

---

## Contexto

2026-09-21: disco C: (Windows/WSL2) a 9.1GB livres/477GB (99%). Causa raiz: `docker_data.vhdx`
(backend WSL2 do Docker Desktop) em 88GB, nunca compactado — `docker system prune` libera espaço
*dentro* do vhdx, mas o arquivo NTFS não encolhe sozinho. Mitigado manualmente (55.6GB + 3.96GB
liberados via prune, compactação bloqueada por um lock de arquivo persistente que não foi possível
isolar sem `wsl --shutdown`, o que mataria a própria sessão do agente — ver D-2026-09-21-1 em
DECISIONS.md e o runbook `docs/how-to/docker-disk-cleanup.md`).

Esta spec fecha o item de backlog registrado em `ROADMAP.md` ("Docker disk lifecycle — backlog"):
transformar a resposta reativa de hoje em prevenção automática, sem depender de alguém notar o
disco cheio de novo.

## Escopo

Dentro:
1. Prune seguro automático e periódico (dangling images + build cache) — nunca toca imagem com tag
   nem volume.
2. Checagem periódica de saúde de disco (tamanho do `docker_data.vhdx` + espaço livre em C:) com
   alerta explícito em log antes de virar incidente.
3. Flag (não deleção automática) de imagens com tag de rollback/backup (`*-rollback`, `*-pre-*`)
   mais velhas que um limite — decisão de apagar continua manual/humana.
4. Decisão explícita sobre compactação do `.vhdx`: **fica manual/sob demanda**, não automatizada
   agora (ver Decisão D4 abaixo) — o guard só avisa quando o threshold é cruzado, apontando pro
   runbook.

Fora:
- Monitoramento via Prometheus/Grafana (não existe exporter de métricas de host Windows/WSL2 nesta
  stack hoje — adicionar um `windows_exporter`/`node_exporter` seria um projeto à parte, não
  justificado só por isto agora). Fica registrado como possível upgrade futuro, não bloqueia esta spec.
- Upload/retenção de backup do próprio vhdx (não é dado de produto, é cache reconstruível).
- Automação da compactação em si (decisão D4).

## Decisões

- **D1 — cadência**: diária, via cron, mesmo padrão do `backup.sh` já existente (`0 3 * * *`).
  Guard roda em `0 3 30 * * *`... (cron não tem segundos — na prática `35 3 * * *`, 35min depois do
  backup, evita contenção de I/O com o backup rodando ao mesmo tempo).
- **D2 — thresholds**: WARN se `docker_data.vhdx` > 40GB OU espaço livre em C: < 20GB. Valores
  escolhidos com folga sobre o crash de hoje (88GB / 9GB livres) — dão tempo de agir antes de
  virar emergência de novo, sem gerar alerta em todo boot.
- **D3 — destino do alerta**: log dedicado (`~/logs/docker-disk-guard.log`), mesmo padrão já usado
  pelo cron de `onboarding-reminder` existente. Sem integração com Grafana/GlitchTip agora (fora de
  escopo, ver acima) — aceito como limitação conhecida, não silenciosa.
- **D4 — compactação do vhdx**: **não automatizada**. Motivos: (a) exige elevação de Administrador,
  não seguro de automatizar sem supervisão a partir de uma sessão não-interativa; (b) tentativa real
  hoje (2026-09-21) falhou 3x por lock de arquivo mesmo com Docker Desktop/serviço/distro parados —
  rodar isso desatendido via cron correria o risco de ficar preso ou (pior) forçar algo destrutivo
  sem supervisão; (c) parar o Docker Desktop automaticamente de madrugada derrubaria os 33
  containers do stack local sem aviso. O guard script detecta o threshold e **avisa**, apontando
  pro runbook — a execução continua manual e supervisionada.
- **D5 — retenção de tags rollback**: flag, não deleção automática. Limite: 14 dias (mesma ordem de
  grandeza da retenção semanal do backup.sh). Decisão de apagar continua sempre humana — imagem de
  rollback existe justamente pra não confiar em automação nessa hora.

## Done Criteria

1. `scripts/docker-disk-guard.sh` criado: roda o prune seguro, mede vhdx + espaço livre, aplica os
   2 thresholds (D2), lista tags rollback/pre-* com mais de 14 dias sem apagar (D5).
2. `shellcheck` limpo (gate externo, mesmo padrão de `pre-commit.sh`).
3. Rodado manualmente pelo menos uma vez, de verdade (não só sintaxe) — output real revisado.
4. Cron instalado (`crontab -l` mostra a entrada) — ativação do daemon `cron` em si já é
   responsabilidade prévia do usuário (mesmo gap conhecido do `backup.sh`, não reaberto aqui).
5. `docs/how-to/docker-disk-cleanup.md` atualizado linkando o guard script (evita o runbook ficar
   órfão do que agora roda sozinho).
6. `ROADMAP.md`: item "Docker disk lifecycle — backlog" fechado/atualizado refletindo o que foi
   implementado vs. o que ficou deliberadamente de fora (D4, Prometheus/Grafana).
7. Registro em `.specs/audit/execution.md` e `.specs/project/DECISIONS.md`.

## Tasks

| # | Task | Status |
|---|---|---|
| 1 | `scripts/docker-disk-guard.sh` (prune + thresholds + flag de rollback tags) | ✅ DONE |
| 2 | shellcheck PASS | ✅ DONE (0 findings, exit 0) |
| 3 | Execução real manual + revisão do output | ✅ DONE — rodado de verdade, ambos thresholds dispararam WARN corretamente (vhdx 87GB, C: 5GB livres — piorou desde a sessão anterior, ver nota abaixo), 0 tags rollback flagged (a `pre-spec77-rollback` já tinha sido removida pelo prune agressivo aprovado antes, confirmado via `docker images` real) |
| 4 | Entrada no crontab | ✅ DONE (`35 3 * * *`), daemon `cron` confirmado `running` nesta máquina — sem o gap de `backup.sh` (sudo pendente) |
| 5 | Atualizar runbook + ROADMAP | ✅ DONE |
| 6 | Registro final (audit/decisions/state) | ✅ DONE |

## Achado durante a execução (não estava no escopo original, registrado)

C: caiu de 8.2GB → 5GB livres entre o fim da sessão anterior e agora (poucos minutos), sem nenhuma
ação nossa no meio — consumo ativo por outro processo do Windows (não investigado, fora de escopo
desta spec). Reforça que os thresholds (D2) estão bem calibrados: já dispararam WARN de verdade na
primeira execução. Usuário deve rodar a compactação manual (runbook) o quanto antes — a folga que
o D2 pretendia dar (20GB) já foi corroída antes mesmo do guard entrar em produção.
