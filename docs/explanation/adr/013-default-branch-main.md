# ADR 013: Branch principal padrão = `main` em todos os repos

## Status
Aceita — 2026-09-08

## Contexto
`infra-platform` usava `master` como branch principal (herdado do default antigo do git,
nunca decidido conscientemente). Usuário pediu a troca pra `main` neste repo e que isso
vire padrão pra todos os projetos (existentes e novos), não uma decisão pontual.

## Decisão
Toda branch principal, em todo repo sob este workspace, se chama `main`. Nenhum repo deve
usar `master` daqui em diante. Se algum script/CI/doc referenciar `master` como nome de
branch (não confundir com termos técnicos não-relacionados, ex. `sqlite_master`), corrigir
pra `main` ao encontrar.

## Varredura executada em 2026-09-08 (todos os repos sob `~/projects/`)
| Repo | Owner | Estava | Ação |
|------|-------|--------|------|
| `infra-platform` | rastaFul | `master` | Renomeado → `main` |
| `dev-environment` | rastaFul | `master` | Renomeado → `main` |
| `artists-booking` | rastaFul | `main` | Já conforme, nada a fazer |
| `microgrow` | rastaFul | `main` | Já conforme, nada a fazer |
| `rastafinancas` | rastaFul | `main` | Já conforme, nada a fazer |
| `vetcare` | rastaFul | `main` | Já conforme, nada a fazer |
| `agents-harness` | rastaFul | `main` | Já conforme, nada a fazer |
| `developerFolio` | rastaFul (fork público) | `master` | **Renomeado → `main` (2026-09-21, via `harness-dev`)**. Feature `rename-branch-master-main`, decisão do item 6 tomada pelo usuário: opção b, alinhar deploy pra `-b gh-pages`. `package.json`/`deploy.yml`/`prettier.yml` editados, branch renomeada no GitHub, `master` remoto deletado. Verificado externamente por `harness-infra`: `git ls-remote --heads origin` só lista `main`/`gh-pages`/`feature/*` (sem `master`), `git branch -a` sem refs de `master` após `fetch --prune`, `grep -rn master .github/workflows/` = 0 ocorrências, `origin/HEAD -> origin/main` confirmado. Commit `de2d176` ("chore: atualizar CI/scripts para branch main"), pushed. |
| `tldr-projects` | sem remote | `master` | **Renomeado → `main` (via `harness-dev`)**. A branch `main` órfã que bloqueava o rename foi resolvida (não registrado em spec própria do repo, mas confirmado por evidência externa: `git reflog show main` mostra `Branch: renamed refs/heads/master to refs/heads/main` na raiz do histórico real, sem nenhum commit órfão "first commit" sobrando). Sem remote configurado neste repo (`git remote -v` vazio) — rename é só local, não há `origin/master` pra deletar nem CI pra atualizar. |
| `url-shortener` | thiagomr (não é rastaFul) | `feature/pipelines` | Fora de escopo — repo de outro owner/colaboração, convenção deste workspace não se aplica sem confirmação. |
| `cron-monitoring`, `gorila`, `logger-lib` | — | não são repos git | N/A |

## Como aplicar num repo existente
```bash
git branch -m master main
git push -u origin main
gh repo edit <owner>/<repo> --default-branch main
git push origin --delete master
```
Pré-checagem obrigatória antes de rodar em qualquer repo: sem PR aberto contra `master`, sem
workflow/doc referenciando `master` como branch (CI, branch protection rules, links em docs).
Se houver PR aberto ou branch protection configurada em `master`, resolver isso primeiro —
não é mais um rename de 30 segundos.

## Consequências
- Alinha com o default atual do GitHub para repos novos — reduz fricção, não aumenta.
- Repos existentes não migrados ainda ficam temporariamente inconsistentes (`master`) até
  serem tocados — aceitável, não é retrabalho forçado só por isso.
- Nenhuma mudança de CI necessária aqui: `infra-platform` não tinha workflow referenciando
  `master` por nome no momento da troca.

## Fechamento — 2026-09-21
Os 2 únicos repos escalados (`developerFolio`, `tldr-projects`) foram migrados pelo usuário via
`harness-dev`. Varredura de 2026-09-08 está 100% aplicada — todo repo `rastaFul` sob `~/projects/`
usa `main`. `url-shortener` (outro owner) e os não-repos-git seguem fora de escopo por decisão
original, não pendência. Ver D-2026-09-21-5 em `.specs/project/DECISIONS.md`.
