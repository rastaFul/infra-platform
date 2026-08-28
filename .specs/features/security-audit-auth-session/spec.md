# SPEC: Security Audit — Auth & Session (por produto)

## Status: INVESTIGAÇÃO CONCLUÍDA (2026-08-28) — correções ficam pra spec própria (Done Criteria #3)
## Created: 2026-08-27
## Updated: 2026-08-28 — auditoria feita diretamente (sub-agentes indisponíveis nesta sessão), evidência real por arquivo:linha
## Owner: rodrigo

---

## Contexto

`security-hardening-phase1` achou 1 crítico (JWT fallback) só de auditar CORS de passagem. Esta spec formaliza uma auditoria completa de autenticação/sessão nos 4 produtos — não foi feita ainda, ao contrário da Fase 1 (que já tem achados concretos), aqui o trabalho É a investigação.

## Objetivo

Respondido, com evidência (código lido, não suposição), por produto:

| Pergunta | artists-booking | rastafinancas | microgrow | vetcare |
|---|---|---|---|---|
| Hash de senha | bcryptjs, **10 rounds** (`register.use-case.ts:28`) | bcryptjs, **12 rounds** (`auth.ts:8`, via env `BCRYPT_ROUNDS`) | N/A — sem auth de usuário, só rotas de sensor/atuador/config (confirmado: nenhuma referência a bcrypt/jwt/login/password em `api/src`) | N/A — só Google OAuth (`auth.ts`), sem senha nenhuma armazenada |
| Cookies de sessão | `httpOnly`✓ `sameSite:lax`✓ **`secure` ausente** (`auth.routes.ts:41,55,69,91`) | `httpOnly`✓ `sameSite:lax`✓ **`secure: isProduction`✓** (`auth.ts:27-40`) — correto | N/A | Gerenciado pelo NextAuth v5 (`session: {strategy:'jwt'}`) — padrão da lib, não código custom |
| Refresh token: rotação/revogação | **Sim** — rotaciona a cada uso, revoga no logout, tabela `refreshToken` com `revokedAt` (`auth.routes.ts:84-91,96-106`) | Sim — `revokeRefreshToken`/`revokeAllUserRefreshTokens` existem (`user-repository.js` via import em `auth.ts:4`) | N/A | Delegado ao NextAuth (JWT strategy, sem refresh token custom) |
| Rate limit em rotas de auth | **Não tem** — só rate limit global, nenhum `config:{rateLimit}` em `auth.routes.ts` (grep vazio) | **Sim, por rota** — login/signup 5/min, reset de senha 3/5min, refresh 20/min (`auth.ts:46,82,127,162,208,237`) | N/A | Login é via Google OAuth — brute-force não se aplica da mesma forma, mas não conferi rate limit no endpoint NextAuth em si |
| JWT: expiração/verificação | access 15m, refresh 30d (`jwt.service.ts`) — razoável. Verificação via `app.authenticate` preHandler (`auth.plugin.ts`) | access 1h, refresh 7d (env `JWT_EXPIRES_IN`/`REFRESH_TOKEN_EXPIRES_IN`) — razoável | N/A | JWT gerenciado pelo NextAuth internamente |
| Outros secrets hardcoded | Nenhum outro achado (só o já corrigido) | Nenhum outro achado | N/A | `trustHost: true` no NextAuth — desabilita validação de Host header própria da lib; não é secret hardcoded, mas vale checar se `AUTH_URL` está pinado corretamente antes do Oracle (ADR 007) |

## Achados Priorizados

| Prioridade | Achado | Produto | Ação recomendada |
|---|---|---|---|
| 🟠 HIGH | Sem rate limit específico em `/register` e `/login` — só o global (se existir) protege contra brute-force de senha | artists-booking | Copiar o padrão do rastafinancas (`config: { rateLimit: { max: 5, timeWindow: '1 minute' } }`) pras rotas de auth |
| 🟡 MEDIUM | Cookie de refresh token sem `secure` — funciona hoje pq é tudo localhost atrás do Cloudflare Tunnel, mas devia ser `secure: NODE_ENV==='production'` (mesmo padrão do rastafinancas) antes do Oracle (multi-host) | artists-booking | Adicionar `secure: process.env.NODE_ENV === 'production'` nos 4 `setCookie` de `auth.routes.ts` |
| 🟢 LOW | bcrypt 10 rounds — funcional, mas rastafinancas já usa 12 (padrão OWASP atual) | artists-booking | Bump pra 12, migração transparente (bcrypt verifica hash antigo normalmente, só novos hashes usam o rounds novo) |
| 🟢 LOW | `trustHost: true` no NextAuth — confirmar que `AUTH_URL`/`NEXTAUTH_URL` está pinado no `.env` de produção, não confiando em Host header arbitrário | vetcare | Auditoria rápida do `.env` — não é código, é config |

## Nota final

Diferença notável entre os 4: **rastafinancas tem a implementação de auth mais madura** (rate limit por rota já correto desde o início, `secure` condicional, bcrypt 12). artists-booking tem boa arquitetura (rotação de refresh token, revogação) mas ficou pra trás em 2 detalhes (rate limit, `secure`). microgrow e vetcare não têm superfície de auth custom relevante (microgrow não tem auth de usuário; vetcare delega tudo pro NextAuth+Google).

## Done Criteria

1. Tabela acima preenchida com achados reais, por produto, com arquivo:linha de evidência.
2. Cada gap encontrado vira uma linha de ação priorizada (CRITICAL/HIGH/MEDIUM/LOW), mesmo formato do `security-hardening-phase1`.
3. Nenhuma correção aplicada nesta fase — só levantamento. Correções viram uma spec de execução separada, com aprovação por item (o achado do JWT_SECRET mostrou que "auditoria rápida" já acha coisa séria — não misturar leitura com escrita sem revisão).

## Tasks

| # | Task | Método |
|---|---|---|
| 1 | Auditoria artists-booking (auth completo: register/login/refresh/logout) | `infra-analyzer` ou leitura direta |
| 2 | Auditoria rastafinancas (mesmo escopo) | idem |
| 3 | Auditoria vetcare (mesmo escopo — é NextAuth ou custom?) | idem |
| 4 | Auditoria microgrow (confirmar se tem auth de usuário real ou só chave de API/dispositivo) | idem |
| 5 | Consolidar achados + priorizar | orquestrador |

## Nota

Delegar pro sub-agente `infra-analyzer` ou `code-analyzer` (read-only, retorna relatório estruturado) em vez de eu fazer investigação ad-hoc — encaixa exatamente no propósito desses sub-agentes.
