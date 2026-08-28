# SPEC: Dev Environment — Bootstrap via Ansible

## Status: DRAFT (aguardando detalhes do setup Vagrant existente do usuário)
## Created: 2026-08-27
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

## Decisões Necessárias

- [ ] D1: usuário já tem um repo Vagrant existente — precisa ver o conteúdo antes de escrever tasks detalhadas, pra não duplicar/contradizer o que já funciona nas outras máquinas
- [ ] D2: esse repo é público ou privado? (dotfiles geralmente podem ser públicos, mas confirmar)
- [ ] D3: mantém Vagrant em paralelo pras máquinas que já usam (migração gradual), ou substitui de uma vez?

## Fora de Escopo

- Provisionamento de VMs cloud (isso é Terraform, `infra-platform/terraform/modules/oci-compute/`) — Ansible aqui é só a camada de configuração da máquina de DEV pessoal, não de servidor
