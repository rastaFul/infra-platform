# Need: `Harness Gates` CI blocked by GitHub Actions artifact storage quota

**Origem:** achado em `rastafinancas` (sessão `harness-dev`, 2026-09-17, spec local
`ci-fully-green`) enquanto se deixava o CI daquele repo verde. Registrado aqui a pedido explícito
do usuário: **"Essa é uma definição para o harness de infra. Apenas registre a spec no projeto de
infra platform, e depois eu lido com isso."** — este documento é levantamento de problema, não
prescrição de solução. Decisão de COMO resolver fica pro `harness-infra` (tem as skills de infra
pra decidir melhor).

**Status:** `harness-dev` não vai agir sobre isso. Não escalado como bloqueante agora — usuário
confirmou que tudo bem aguardar o prazo/reset da quota por enquanto ("na afinal fazemos os deploys
local por enquanto"). Sem urgência real hoje, mas é um problema estrutural do template
compartilhado, não pontual de um repo.

## O que foi observado (fato, não interpretação)

No workflow `Harness Gates` (`.github/workflows/gates.yml`, instalado via
`agents-harness/claude/install.sh` — mesmo template usado por `artists-booking`, `microgrow`,
`rastafinancas`, `vetcare`, e o próprio `infra-platform`, per `harness-gates-rollout` spec), o job
`build-sandbox` builda a imagem sandbox (`docker build` a partir de `.harness-sandbox/docker/
Dockerfile.sandbox`), salva com `docker save`, e sobe via `actions/upload-artifact@v4`
(`name: harness-sandbox-image`, `retention-days: 1`) — o job seguinte (`dev-gates`) baixa esse
artifact pra rodar os gates dentro do mesmo container (garantia de "local == CI", ver comentário no
próprio `gates.yml`).

Em `rastafinancas`, esse upload falha com:
```
##[error]Failed to CreateArtifact: Artifact storage quota has been hit. Unable to upload any
new artifacts. Usage is recalculated every 6-12 hours.
```

Confirmado via `gh run view --log-failed` (não é suposição). A mensagem indica que é **quota no
nível da conta GitHub** (`rastaFul`), não algo isolado a este repo/workflow.

## Por que isso é relevante pra `infra-platform`, não só `rastafinancas`

`gates.yml` é o MESMO template, instalado do mesmo jeito, em pelo menos 5 repos sob esta conta
(4 produtos + `infra-platform`). Se a quota está sendo estourada, é provável que:
- O mesmo `build-sandbox`→`upload-artifact` bata na mesma quota nos outros repos também (não
  verificado em todos — só confirmado em `rastafinancas` até agora).
- O padrão em si (`docker save` + `upload-artifact` de uma imagem Docker inteira, `retention-days:
  1`, repetido a cada push/PR em N repos) pode ser o que está consumindo a quota mais rápido do que
  o esperado — não investigado a fundo aqui (ver "Perguntas / investigação necessária" abaixo).

## O que NÃO está nesta spec (deliberado)

Nenhuma solução está prescrita aqui. Não é papel do `harness-dev` decidir se a resposta certa é
esperar, limpar artifacts manualmente, upgrade de plano, trocar `upload-artifact` por
`actions/cache`, consolidar `build-sandbox`+`dev-gates` num único job, reduzir `retention-days`,
usar um registry (GHCR, já usado por `publish-image` no mesmo `gates.yml`) em vez de artifact pra
passar a imagem entre jobs, ou qualquer outra abordagem — isso é decisão de arquitetura do template
compartilhado, e o `harness-infra` tem contexto/skills de infra que este agente não tem pra decidir
o trade-off certo.

## Perguntas / investigação que provavelmente o `harness-infra` vai precisar fazer

- Isso está acontecendo nos outros repos que usam o mesmo `gates.yml` (`artists-booking`,
  `microgrow`, `vetcare`, e o próprio `infra-platform`)? Não verificado ainda.
- Quanto da quota da conta é consumido especificamente por `harness-sandbox-image` vs. outros
  artifacts (builds antigos, outros workflows)? GitHub expõe isso em Settings → Billing → Actions
  (ou via API de artifacts por repo).
- O padrão `build-sandbox`→`upload-artifact`→`dev-gates` é estrutural do template
  (`agents-harness`) ou pode ser revisto sem quebrar a garantia "local == CI" que o comentário no
  `gates.yml` documenta como hard constraint?

## Estado atual em `rastafinancas` (referência, não ação pedida aqui)

Usuário optou por aguardar o reset natural da quota (6-12h, mensagem oficial do erro) — sem pressa,
já que o deploy real daquele projeto hoje é local (Docker Compose + Cloudflare Tunnel, `oci-free`
ainda não provisionado). `ci.yml` daquele repo já está 100% verde independente disso; só o
`Harness Gates` fica bloqueado nesse ponto. Detalhe completo:
`rastafinancas/.specs/features/ci-fully-green/QUESTIONS.md` (item 1).
