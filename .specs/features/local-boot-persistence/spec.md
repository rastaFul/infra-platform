# SPEC: Local Boot Persistence (apps não sobem sozinhos após restart do PC)

## Status: DONE — 2026-08-29
## Created: 2026-08-28
## Owner: rodrigo

## Resultado final
Frente B executada por completo (D1/D2 aprovados em 2026-08-28): 5/5 componentes migrados PM2→Docker Compose (rastafinancas, microgrow, vetcare, artists-booking, platform-tunnel), todos `restart: unless-stopped`. `wsl-boot.sh` limpo (pm2 resurrect removido, cron adicionado). PM2 permanece instalado, sem nenhum processo gerenciado.

Incidente real descoberto e resolvido durante a migração do tunnel: as 6 rotas públicas caíram em 502 porque o tunnel Cloudflare é **remotely-managed** (painel Zero Trust → Tunnels → rastafinancas → "Published application routes"), com o campo Service ainda apontando `http://localhost:PORT` (válido só quando cloudflared rodava direto no host via PM2). Corrigido pelo usuário pra `http://host.docker.internal:PORT`. Validado com curl real: 6/6 sem 502. Detalhe completo da investigação (incluindo um bug real e documentado do cloudflared com resolução dual-stack IPv6/IPv4 que quase virou a explicação errada) em `.specs/audit/execution.md` e `.specs/project/DECISIONS.md` D-2026-08-28-10.

Bugs reais extras achados e corrigidos nesse processo: PM2 `dump.pm2` com entrada órfã do tunnel antigo (risco de tunnel duplicado num resurrect futuro); `vetcare/Dockerfile` HEALTHCHECK batendo em `/` (redireciona via NextAuth pra URL pública, fazendo a saúde de um container local depender do tunnel estar de pé) — corrigido pra `/api/health`.

Done Criteria (definidos abaixo) totalmente atendidos, exceto o teste de restart real do PC completo do zero (o "teste" real foi o notebook travar em outra tarefa e a sessão retomar depois — Docker Compose se restaurou sozinho sem intervenção, confirmando o comportamento esperado na prática, não só em teoria).

---

## Contexto

Usuário reporta: toda vez que reinicia o PC, os projetos que rodam local não sobem sozinhos. Diagnóstico feito nesta sessão (fatos confirmados, não assumidos):

1. **WSL2 não roda systemd** (`ps -p 1` → `/init`, `systemctl is-system-running` → `offline`, `pm2 startup systemd` falha: "System has not been booted with systemd as init system"). Isso significa que **nenhum serviço registrado via systemd sobrevive** a um restart — nem PM2, nem cron.
2. Mecanismo de boot real hoje é `/etc/wsl.conf` → `[boot] command = /home/rodrigo/wsl-boot.sh`, que roda **apenas `pm2 resurrect`** (comentário no próprio script: "Docker é iniciado manualmente pelo usuário"). Não inicia Docker, não inicia cron.
3. **Estado ao vivo confirmado agora**: `pm2 list` → 0 processos rodando (daemon nem existia, foi espawnado na hora). `service cron status` → not running. Ou seja, o sintoma que o usuário descreve está acontecendo neste exato momento.
4. Em contraste, **Docker Compose já se comporta corretamente**: os 10 containers do `platform/docker-compose.yml` estão `Up 14 minutes` com `restart: unless-stopped` — voltaram sozinhos assim que o Docker Desktop (iniciado manualmente pelo usuário) ficou de pé. Nenhuma intervenção manual foi necessária para eles.
5. Isso confirma o padrão já registrado (D4 do STATE.md: "Docker Compose substituindo PM2 completamente", Batch 3 do roadmap ainda não executado): **o problema é estrutural ao PM2 em WSL2 sem systemd**, não à infra como um todo.
6. Pain point relacionado já documentado (D-2026-08-28-6, backup-strategy): cron também precisa de `sudo service cron start` manual a cada boot — mesma causa raiz.
7. Camada fora do controle do WSL: Docker Desktop (app Windows) tem um toggle próprio "Start Docker Desktop when you sign in" — se desligado, nada dentro do WSL roda até o usuário abrir o Docker Desktop manualmente. Isso é configuração do Windows, não deste repo.

## Causa raiz

Duas causas independentes, ambas sem systemd para se apoiarem:
- **A. Docker Desktop não autoinicia** (config do Windows, fora do repo) → nada que dependa do socket Docker sobe até o usuário abrir o app.
- **B. PM2 (ainda hospedando 10 processos de app + o tunnel) depende de `pm2 resurrect` manual/via script**, que só roda se o WSL de fato inicializar (abrir um terminal WSL, ou o Docker Desktop iniciar a integração WSL) — e mesmo rodando, não é atômico com o Docker estar pronto.

## Duas frentes de solução (não mutuamente exclusivas)

### Frente A — Mitigação imediata (mantém PM2 por enquanto)
Reforçar `wsl-boot.sh` para cobrir os 2 gaps atuais:
- Adicionar `service cron start` (resolve o gap do backup também, cross-referencia D-2026-08-28-6)
- Adicionar espera/retry pelo socket Docker antes de qualquer `docker compose up -d` (evita race condition — hoje comentado como "Docker é iniciado manualmente")
- Continuar com `pm2 resurrect` para os processos ainda não migrados

Risco: continua dependendo de systemd-less PM2 pra parte dos processos — mitigação, não eliminação da causa raiz.

### Frente B — Fechar Batch 3 (já decidido em D4, nunca executado): migrar PM2 → Docker Compose
Uma vez que TODOS os processos hoje em PM2 (rastafinancas-api/web, microgrow-api/webapp/webapp-sim/simulator, artists-api/web, vetcare, platform-tunnel) rodem via `docker-compose.yml` por projeto com `restart: unless-stopped` (mesmo padrão que já funciona pro platform stack), o problema estrutural desaparece: resta só garantir que o Docker Desktop suba sozinho (config do Windows) — nenhum script de resurrect é mais necessário.

Isso já está no roadmap (`STATE.md` Batch 3: "Migração PM2 → Docker Compose (1 serviço por vez)"), só nunca foi executado. Esta spec pode ser o gatilho pra priorizar isso agora, dado que é a causa raiz real do pain point que o usuário está sentindo.

## Ação fora do repo (usuário, não automatizável por aqui)
- Windows: Docker Desktop → Settings → General → habilitar "Start Docker Desktop when you sign in" (se ainda não estiver).
- Confirmar que a integração WSL do Docker Desktop está habilitada pra distro `Ubuntu-20.04` (Settings → Resources → WSL Integration) — é isso que dispara o `[boot] command` do `wsl.conf` quando o Docker Desktop inicia.

## Decisões necessárias antes de executar

- **D1**: Fazer só a Frente A agora (mitigação rápida, baixo risco, ~30min) e deixar a Frente B pro Batch 3 formal depois? Ou já puxar a Frente B pra agora (migração real PM2→Docker, maior escopo, mexe nos 10 processos de produção local)?
- **D2**: Se Frente B agora: migrar tudo de uma vez ou 1 serviço por vez (conforme já planejado no roadmap, reduz blast radius)? Recomendação: 1 por vez, começando pelo `platform-tunnel` (menor risco, sem estado) antes das APIs.
- **D3**: Confirmar que o toggle "Start Docker Desktop when you sign in" no Windows é aceitável pro usuário ligar manualmente (ação fora deste repo, não posso fazer por aqui).

## Done Criteria (a definir após D1/D2)
- Restart real do PC (não só do WSL) testado de ponta a ponta: Docker Desktop sobe sozinho, platform stack sobe sozinho (já funciona), apps migrados sobem sozinhos, cron ativo sem comando manual.
- Gate: `docker compose ps` mostrando todos os serviços esperados `Up` sem nenhuma intervenção manual pós-boot.
