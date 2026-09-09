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
| `developerFolio` | rastaFul (fork público) | `master` | **Não renomeado** — fork ativo com `gh-pages` + 2 branches de feature, 2 workflows (`deploy.yml`, `prettier.yml`) referenciam `master` por nome, deploy real de site público. Rename exige editar os workflows junto (não é só metadado) — escalado ao usuário antes de agir. |
| `tldr-projects` | sem remote | `master` | **Não renomeado** — anomalia encontrada: já existe uma branch `main` local órfã (1 commit "first commit", histórico não relacionado ao trabalho real em `master`) + ref remota `origin/main` órfã sem remote configurado (`git remote -v` vazio). `git branch -m` falha (`main` já existe). Working tree com mudanças não commitadas de outra frente (reddit feature). Escalado ao usuário — decisão de descartar branch órfã não é do agente. |
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
