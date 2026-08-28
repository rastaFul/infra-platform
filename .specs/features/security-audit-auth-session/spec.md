# SPEC: Security Audit — Auth & Session (por produto)

## Status: DRAFT (investigação ainda não feita)
## Created: 2026-08-27
## Owner: rodrigo

---

## Contexto

`security-hardening-phase1` achou 1 crítico (JWT fallback) só de auditar CORS de passagem. Esta spec formaliza uma auditoria completa de autenticação/sessão nos 4 produtos — não foi feita ainda, ao contrário da Fase 1 (que já tem achados concretos), aqui o trabalho É a investigação.

## Objetivo

Responder, com evidência (código lido, não suposição), por produto:

| Pergunta | artists-booking | rastafinancas | microgrow | vetcare |
|---|---|---|---|---|
| Hash de senha: algoritmo? (bcrypt/argon2/scrypt — nunca MD5/SHA simples) | ? | ? | ? | ? |
| Cookies de sessão: `httpOnly`+`secure`+`sameSite`? | ? | ? | N/A (sem sessão de usuário?) | ? |
| Refresh token: rotação? Revogação em logout? | ? | ? | N/A | ? |
| Rate limit em rotas de auth especificamente (não só global)? | ? | ? | N/A | ? |
| JWT: tempo de expiração razoável? Assinatura verificada em toda rota protegida? | ? | ? | N/A | ? |
| Outros secrets hardcoded como fallback (além do já achado)? | ? | ? | ? | ? |

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
