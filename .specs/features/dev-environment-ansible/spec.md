# SPEC: Dev Environment — Bootstrap via Ansible

## Status: APPROVED (aguardando só D2 — visibilidade do repo)
## Created: 2026-08-27
## Updated: 2026-08-27 — usuário confirmou: não existe repo pessoal ainda (só da empresa, fora de escopo/acesso). Começa do zero, sem legado pra respeitar.
## Owner: rodrigo

---

## Contexto

Usuário já pratica versionar o ambiente de dev (git + Vagrant) para migrar entre máquinas — hoje WSL2, também Linux nativo em outros lugares, planeja Mac. Perguntou o que fazer especificamente no WSL2 atual, e se dá pra fazer tudo só com Ansible.

**Resposta técnica:** sim, e é melhor fit que Vagrant para este caso específico:
- WSL2 já É uma VM (Hyper-V) — rodar Vagrant (VirtualBox/libvirt) *dentro* dele seria virtualização aninhada, frágil, sem instalação hoje (confirmado: nenhum provider de Vagrant presente neste WSL2).
- O que precisa portar entre WSL2 / Linux nativo / Mac não é a camada de VM (cada plataforma já resolve isso à sua maneira — WSL2 nativamente, Linux não precisa, Mac só precisaria se quisesse Linux real em vez de macOS), é o que tem **dentro**: dotfiles + pacotes + configuração de ferramentas.
- Ansible cobre isso nativamente, sem VM: `ansible-playbook -i localhost, -c local` roda idempotente em qualquer POSIX (WSL2 Ubuntu, Linux nativo, macOS com `community.general` + Homebrew module). Mesmo playbook, providers de pacote condicionais por SO.
- Bônus: os mesmos playbooks reaproveitam pra provisionar VMs reais depois (Oracle `oci-free`, ADR 007) — Terraform cria a VM, Ansible configura o que tem dentro. Combinação padrão da indústria (Terraform = infra, Ansible = configuração), evita reinventar em shell script solto.

`agents-harness` já prova que esse padrão (repo git + bootstrap idempotente) funciona bem — é o modelo a replicar aqui, só que pro SO inteiro, não só pro Claude Code.

## Objetivo

Repo novo `dev-environment` com playbooks Ansible que deixam uma máquina nova (WSL2 Ubuntu, Linux nativo, ou Mac) pronta em uma execução, sem passos manuais além dos que são genuinamente impossíveis de automatizar (login em contas, chaves SSH pessoais).

## Escopo (proposto — confirmar com usuário antes de detalhar tasks)

- **Dotfiles**: `.bashrc`/`.zshrc`, `.gitconfig`, aliases, `.tmux.conf` (se usar)
- **Pacotes base**: git, docker, gh CLI, nvm+node, pnpm (pinado, ver `docker-build-conventions.md` — mesma lição: nunca `@latest`), terraform, ansible (self-bootstrap)
- **`agents-harness`**: clonar + rodar `install.sh` — reusa o que já existe, não duplica
- **Recuperação de SSH/credenciais**: documentar procedimento (não pode automatizar geração de chave nova sem invalidar acesso existente) — playbook verifica presença e avisa se faltando, não gera sozinho
- **Docker Desktop / WSL2 integration**: específico de Windows, fica documentado como pré-requisito manual (não instalável via Ansible de dentro do WSL2)

## Done Criteria

1. `ansible-playbook site.yml` roda limpo (idempotente — rodar 2x não muda nada na 2ª vez) numa instalação Ubuntu fresca dentro do WSL2
2. Mesmo playbook roda em Linux nativo (testável, mesmo que não tenha a máquina agora — usar `when: ansible_facts['os_family'] == ...` corretamente)
3. Suporte Mac via Homebrew documentado/preparado, mesmo que não testável ainda (usuário ainda não tem Mac)
4. `README.md` cobrindo os passos manuais irredutíveis (login GitHub, SSH key, Docker Desktop no Windows)
5. Sem segredos no repo — só estrutura/config, credenciais reais ficam fora (gerenciador de senha pessoal do usuário)

## Decisões

- [x] D1: **resolvido** — não existe repo Vagrant pessoal (só da empresa, fora de escopo). Começa do zero, sem legado pra respeitar/migrar.
- [ ] D2: repo público ou privado? Dotfiles costumam ser públicos (sem segredo dentro, por design — item 5 dos Done Criteria), mas é call sua. **Assumindo privado até você confirmar o contrário** (mesmo padrão dos outros repos infra criados nesta sessão) — não vou criar público sem confirmação explícita.
- [x] D3: **resolvido** — sem Vagrant existente, não há "paralelo" a manter. Ansible desde o início.

## Tasks

| # | Task | Detalhe |
|---|---|---|
| 1 | Criar repo `dev-environment` (privado, pendente D2) | Estrutura Ansible padrão: `site.yml`, `roles/`, `inventory/` |
| 2 | Role `dotfiles` | `.bashrc`/`.zshrc`, `.gitconfig`, aliases — usa os que já existem neste WSL2 (`~/.bashrc` atual) como base, não do zero absoluto |
| 3 | Role `packages` — condicional por SO (`ansible_facts['os_family']`: Debian→apt, Darwin→homebrew) | git, docker (ou Docker Desktop check no Windows/WSL2), gh CLI, nvm+node, pnpm pinado, terraform, corepack |
| 4 | Role `agents-harness` | Clona `github.com/rastaFul/agents-harness` + roda `claude/install.sh` no destino certo |
| 5 | Role `credentials-check` (não gera, só verifica) | Checa presença de `~/.ssh/id_*`, `gh auth status`, avisa o que falta em vez de tentar automatizar login |
| 6 | `README.md` | Passos manuais irredutíveis: Docker Desktop no Windows (WSL2 integration), login inicial GitHub/gh, geração de SSH key nova (se for máquina realmente nova) |
| 7 | Testar em uma instalação WSL2 Ubuntu limpa (ou o mais próximo disso que der pra validar nesta máquina) — confirmar idempotência (rodar 2x, 2ª vez sem mudanças) |

## Fora de Escopo

- Provisionamento de VMs cloud (isso é Terraform, `infra-platform/terraform/modules/oci-compute/`) — Ansible aqui é só a camada de configuração da máquina de DEV pessoal, não de servidor
