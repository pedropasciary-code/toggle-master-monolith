# ToggleMaster — Análise 12-Factor App

Avaliação da aplicação `toggle-master-monolith` **na versão original** contra os 12 fatores,
considerando os dois caminhos de execução: local (Docker Compose) e AWS (EC2 + RDS).
Ao final, o plano de adequação indica o que já foi aplicado nesta fase e o que fica para as próximas.

## Resumo

| # | Fator | Situação (versão original) |
|---|---|---|
| I | Codebase | ✅ Atendido |
| II | Dependências | 🟡 Parcial |
| III | Configurações | 🟡 Parcial |
| IV | Serviços de apoio | ✅ Atendido |
| V | Build, release, run | ❌ Não atendido |
| VI | Processos | ✅ Atendido |
| VII | Vínculo de portas | ✅ Atendido |
| VIII | Concorrência | 🟡 Parcial |
| IX | Descartabilidade | 🟡 Parcial |
| X | Paridade dev/prod | ❌ Não atendido |
| XI | Logs | 🟡 Parcial |
| XII | Processos de administração | 🟡 Parcial |

**Placar:** 4 atendidos · 6 parciais · 2 não atendidos.

## Análise por fator

### I. Codebase — ✅ Atendido
**Hoje:** um único repositório Git, do qual saem vários deploys (local e EC2).
**Melhoria:** versionar releases com tags (`v1.0.0`) para rastrear o que está em cada ambiente.

### II. Dependências — 🟡 Parcial
**Atende:** dependências Python declaradas em `requirements.txt` com versão fixa.
**Não atende:**
- Dependências transitivas não estão travadas (sem lockfile com hashes).
- A versão do Python não é declarada fora do Dockerfile; no caminho EC2 depende do SO.
- `psycopg2-binary==2.9.5` não tem wheel para Python 3.12+ e quebra a instalação em distribuições recentes.
- A imagem usa Python 3.9, já fora de suporte.

**Alterações:** lock com `pip-tools` (`pip-compile --generate-hashes`), declarar a versão do Python,
atualizar para Python 3.12 e `psycopg2-binary>=2.9.10`.

### III. Configurações — 🟡 Parcial
**Atende:** as credenciais do banco vêm de variáveis de ambiente (`DB_HOST`, `DB_NAME`, `DB_USER`,
`DB_PASSWORD`); nenhuma credencial está no código Python.
**Não atende:**
- `DB_PORT` é exigido pelo `entrypoint.sh`, mas ignorado pelo `app.py`.
- Não há validação na inicialização: variável ausente só aparece como erro na primeira requisição.
- Porta e bind do Gunicorn estão fixos no Dockerfile e no entrypoint.
- O `docker-compose.yaml` traz usuário e senha em texto claro, versionados.
- No guia da EC2, as variáveis são definidas por `export` na sessão SSH e se perdem ao desconectar.

**Alterações:** ler `DB_PORT`, falhar rápido se faltar variável, parametrizar porta e workers,
tirar segredos dos arquivos versionados (`.env` fora do Git) e usar um cofre de segredos
(AWS Secrets Manager) em produção.

### IV. Serviços de apoio — ✅ Atendido
**Hoje:** o PostgreSQL é um recurso anexado. Trocar o Postgres local pelo Amazon RDS exige só mudar
variáveis de ambiente, sem alterar código.
**Melhoria:** expor `sslmode` por configuração para forçar TLS até o RDS.

### V. Build, release, run — ❌ Não atendido
**Hoje:** na EC2 o "build" acontece no próprio servidor (`git clone` + `pip install`). Não existe artefato
imutável e versionado, nem release identificável (build + config). No Compose, o volume `.:/app`
sobrescreve o código da imagem em tempo de execução, misturando build e run.
**Alterações:** gerar a imagem Docker em pipeline de CI com tag pelo SHA do commit e publicá-la no
Amazon ECR; o deploy apenas executa uma tag específica, com a configuração injetada no release.
Rollback passa a ser voltar para a tag anterior.

### VI. Processos — ✅ Atendido
**Hoje:** a aplicação é stateless. Não guarda sessão, cache nem arquivo local; todo estado vive no
PostgreSQL. Qualquer instância atende qualquer requisição.

### VII. Vínculo de portas — ✅ Atendido
**Hoje:** a aplicação é autocontida e exporta HTTP pelo Gunicorn, sem depender de servidor web
injetado em tempo de execução.
**Melhoria:** tornar a porta configurável.

### VIII. Concorrência — 🟡 Parcial
**Atende:** por ser stateless, pode escalar horizontalmente.
**Não atende:**
- Gunicorn sobe com o padrão de 1 worker síncrono.
- Cada requisição abre e fecha uma conexão com o banco, sem pool; ao escalar, as conexões no RDS
  crescem sem controle.
- Uma única EC2, sem escala automática.

**Alterações:** workers configuráveis, pool de conexões (`psycopg2.pool`, PgBouncer ou RDS Proxy) e,
nas próximas fases, réplicas em containers com auto scaling.

### IX. Descartabilidade — 🟡 Parcial
**Atende:** inicialização rápida; Gunicorn trata `SIGTERM` com encerramento gracioso.
**Não atende:**
- No guia da EC2, a aplicação roda em foreground: cai ao fechar o SSH e não reinicia sozinha.
- O `entrypoint.sh` espera o banco em loop infinito, sem timeout.
- Falhas na criação da tabela são engolidas (`|| true` e `try/except` com `print`): o app sobe
  "saudável" sem a tabela.
- O `/health` não verifica o banco, então não serve como sinal de prontidão real.

**Alterações:** serviço gerenciado com reinício automático, timeout na espera do banco, falhar se a
inicialização falhar e readiness com `SELECT 1`.

### X. Paridade dev/prod — ❌ Não atendido
**Hoje:** local roda em container com Python 3.9, PostgreSQL 13 e entrypoint que cria a tabela; a EC2
roda em virtualenv com o Python do SO, RDS em outra versão do PostgreSQL e sem entrypoint.

Consequência concreta: no caminho EC2 a tabela `flags` não é criada (só o entrypoint do Docker executa
`flask init-db`) e a primeira escrita falha com `relation "flags" does not exist`.
**Alterações:** mesma imagem em todos os ambientes e mesma versão do PostgreSQL entre local e RDS.

### XI. Logs — 🟡 Parcial
**Atende:** saída em stdout (`print` e Gunicorn), com `PYTHONUNBUFFERED` no Dockerfile.
**Não atende:**
- Sem logging estruturado nem nível de log.
- Exceções nas rotas são devolvidas ao cliente (`details`) e não registradas em log, o que também
  expõe detalhes internos do banco.
- Access log do Gunicorn desligado por padrão.
- Na EC2, a saída fica presa ao terminal SSH.

**Alterações:** `logging` em JSON, access log ligado, remover `details` da resposta e registrar o erro,
coletar via journald / CloudWatch Logs.

### XII. Processos de administração — 🟡 Parcial
**Atende:** a criação do schema existe como comando de administração (`flask init-db`), no mesmo código
e com a mesma configuração da aplicação.
**Não atende:** roda implicitamente a cada boot com erros ignorados e não há migrações versionadas.
**Alterações:** migrações versionadas (Alembic/Flyway) executadas como tarefa única de release.

## Plano de adequação

| Prioridade | Ação | Fatores | Quando |
|---|---|---|---|
| Aplicado na Fase 1 | `app.py` passa a ler `DB_PORT` | III | Esta entrega |
| Aplicado na Fase 1 | Segredos fora do Git: Compose lê `.env` (ignorado), repositório só traz `.env.example` | III | Esta entrega |
| Aplicado na Fase 1 | Na EC2, credenciais no AWS Secrets Manager, lidas pela IAM role e injetadas como variáveis de ambiente pelo systemd | III | Esta entrega |
| Aplicado na Fase 1 | Serviço `systemd` com `Restart=on-failure`, iniciado no boot | IX | Esta entrega |
| Aplicado na Fase 1 | `flask init-db` executado no start do serviço na EC2, como no entrypoint do container | X, XII | Esta entrega |
| Aplicado na Fase 1 | PostgreSQL 16 no Compose, mesma versão do RDS (16.15) | X | Esta entrega |
| Aplicado na Fase 1 | `psycopg2-binary` 2.9.10 · access log do Gunicorn ligado na EC2 · porta do host configurável (`APP_PORT`) | II, XI, III | Esta entrega |
| Alta | Imagem versionada no ECR via CI, mesma imagem em todos os ambientes | V, X | Próximas fases |
| Média | Logs estruturados + CloudWatch, sem vazamento em `details` | XI | Próximas fases |
| Média | Pool de conexões + workers configuráveis via variável | VIII | Próximas fases |
| Média | Migrações versionadas como tarefa de release | XII | Próximas fases |
| Baixa | Lockfile com hashes, Python 3.12, readiness com `SELECT 1` | II, IX | Próximas fases |
