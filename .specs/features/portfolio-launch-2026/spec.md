# Spec (cross-project): Refresh de portfolio (site + currículo) — Set/2026

Status: CONCLUÍDO
Criado em: 2026-09-21T15:08:29-03:00
Concluído em: 2026-09-21T20:30:00-03:00

## Por quê aqui
Trabalho cobre múltiplos repositórios (`developerFolio`, `rastafinancas`,
`infra-platform`, `agents-harness`, `vetcare`) — coordenação cross-project
vive em `infra-platform/.specs/` por convenção
(`docs/reference/repository-layout.md`), cada repo mantém sua própria spec
para as mudanças locais.

## Objetivo
Site (`developerFolio`) e currículo devem refletir o nível técnico atual do
usuário (transição dev backend → DevOps/Platform Engineering), com uma
seção de Projetos real e uma decisão consciente do que vira open source.

## Decisões de negócio (usuário, 2026-09-21)
- `vetcare` e `artists-booking`: produtos com intenção de **comercialização**
  → código nunca público. Site mostra só link do produto ao vivo.
- `rastafinancas`: uso pessoal, sem intenção comercial → aprovado abrir
  código, após remediação de segurança.
- `infra-platform`: aprovado abrir só como vitrine técnica de Platform
  Engineering, após remediação.
- `agents-harness`: aprovado abrir (framework próprio de orquestração de
  agentes de IA spec-driven) — diferencial de currículo.
- `microgrow`: não abre código, aparece só como card de projeto (link do
  site).
- Seção "Projetos" do site mostra os 4 produtos com deploy (vetcare,
  artists-booking, rastafinancas, microgrow) — só link do site, nunca
  código, independente da decisão de open source.
- Seção "Open Source" (GitHub pinned) do site mostra rastafinancas,
  infra-platform e agents-harness, só depois de cada um estar limpo e
  público.

## Sub-specs por repositório
| Repo | Spec local | O que faz |
|---|---|---|
| `vetcare` | (ação direta, sem spec — reversão de estado indevido) | tornar privado agora (estava público, contradiz intenção comercial) |
| `rastafinancas` | `.specs/features/opensource-prep/spec.md` | purgar segredo do histórico git, `.gitignore`, `LICENSE`, abrir |
| `infra-platform` | `.specs/features/opensource-prep/spec.md` (este repo) | trocar UUID do túnel por placeholder, `LICENSE`, gitleaks, abrir |
| `agents-harness` | `.specs/features/opensource-prep/spec.md` | gitleaks (já tem LICENSE e está limpo), abrir |
| `developerFolio` | `.specs/features/site-content-refresh/spec.md` | conteúdo do site + currículo novo |

## Ordem de execução
1. `vetcare` → privado (imediato, feito primeiro por ser correção urgente)
2. Remediação em paralelo: `rastafinancas`, `infra-platform`, `agents-harness`
3. Flip de visibilidade pra público dos 3 repos remediados + pin no perfil GitHub
4. `developerFolio`: conteúdo do site (Experiência, Projetos, Skills,
   Proficiência, link do currículo)
5. Currículo: gerar novo PDF (Playwright print, mantendo layout do atual)

## Licença padrão
Nenhuma licença foi especificada pelo usuário para os repos que abrem código.
Decisão: MIT (permissiva, padrão de mercado para projetos pessoais de
portfolio) — usada em `rastafinancas` e `infra-platform`. `agents-harness`
já tem `LICENSE` própria, mantida como está.

## Gates
Cada sub-spec roda seus próprios gates locais (gitleaks obrigatório antes de
qualquer flip de visibilidade). Este documento só rastreia o todo.

## Resultado final — 2026-09-21T20:30:00-03:00

| Repo | Visibilidade final | Observação |
|---|---|---|
| `vetcare` | PRIVATE | corrigido (estava público por engano) |
| `artists-booking` | PRIVATE | inalterado, conforme decisão |
| `microgrow` | PRIVATE | inalterado, conforme decisão |
| `rastafinancas` | **PUBLIC** | achado crítico não previsto: `apps/api/.env` real (JWT_SECRET, VAPID, Resend, Google/GitHub OAuth secrets) também estava no histórico, não só o `.env.e2e` original. Purgado via `git filter-repo`. Depois de tornar público, o commit antigo continuou acessível por SHA direto (comportamento de cache do GitHub) — **repo inteiro apagado e recriado do zero** pra garantir limpeza total, sem tocar em produção. Usuário optou por não rotacionar os 4 segredos agora; repo segue público mas ele está ciente do risco residual até rotacionar. |
| `infra-platform` | **PUBLIC** | UUID do túnel trocado por placeholder, LICENSE adicionada, gitleaks limpo desde o início (nunca teve segredo real trackeado), revisão manual do usuário aprovada |
| `agents-harness` | **PUBLIC** | `.specs`/docs sanitizados (removidas menções nominais aos 3 repos que continuam privados, mantendo todo o conteúdo de decisão/auditoria) antes de abrir |
| `developerFolio` | PUBLIC (já era) | conteúdo do site + currículo atualizados, pipeline de deploy corrigido (bug pré-existente de Node 18 + npm@latest) |

Pin no perfil GitHub: não é possível via API pública do GitHub — fica como
ação manual do usuário (Settings → Profile → Customize your pins).

**Pendência aberta, fora do controle deste orquestrador**: usuário optou
por não rotacionar `JWT_SECRET`/`RESEND_API_KEY`/`GOOGLE_CLIENT_SECRET`/
`GITHUB_CLIENT_SECRET` do `rastafinancas` agora. Repo está público mesmo
assim, por decisão explícita dele. Recomendação permanece registrada.
