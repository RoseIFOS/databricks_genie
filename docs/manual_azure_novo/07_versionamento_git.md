# 07 — Versionamento com Git + Databricks Git folders

> Como o projeto `databricks_genie` passou a ser versionado: repo próprio no GitHub,
> conexão com o Databricks via **Git folders**, e a disciplina de trabalhar com duas
> cópias (local + workspace). Inclui as pegadinhas que apareceram no caminho.

---

## 0. Diagnóstico (por que precisou de tudo isso)

Antes de commitar, investiguei o repo (comandos **só leitura**):

```bash
git rev-parse --show-toplevel   # qual repo cobre esta pasta?
git remote -v                   # pra qual GitHub aponta?
```

**Descoberta:** `databricks_genie` **não tinha `.git` próprio** — estava debaixo do repo
pai `02_personal_projects`, cujo `origin` apontava pro **`poc-snowflake`** (sobra de um
projeto antigo). Confirmei que nada tinha vazado:

```bash
# rodado na pasta pai
git ls-files                    # só um README.md rastreado -> nada do projeto commitado
```

**Decisão:** dar ao projeto um **repo próprio** + **remote próprio** no GitHub, e conectar
o Databricks via **Git folders**.

---

## 1. Inicializar o repo e o primeiro commit

```bash
cd "c:/Users/rose_/Documents/01_Projects/02_personal_projects/databricks_genie"

git init -b main                # repo novo e independente, branch main
git status                      # conferir o que entra (o .env NAO pode aparecer)
git add .
git commit -m "chore: primeiro commit — projeto BI Conversacional HPN (Databricks + Genie)"
```

**Antes do commit** criei o `.gitignore` protegendo segredos:

```gitignore
.env                        # credenciais do Postgres
docs/manual_azure_antigo/   # PDFs com prints de credenciais
__pycache__/
node_modules/
.databricks/
```

> **Regra de ouro:** segredos entram no `.gitignore` **antes** do primeiro commit —
> assim nunca entram no histórico (que é difícil de limpar depois).

---

## 2. Criar o repo no GitHub e conectar o remote

Criei o repo em `github.com/RoseIFOS/databricks_genie` (vazio, sem README), depois:

```bash
git remote add origin https://github.com/RoseIFOS/databricks_genie.git
git remote -v                   # conferir que NAO e o poc-snowflake
git push -u origin main         # -u vincula o upstream (proximos push sao so "git push")
```

---

## 3. Criar um PAT no GitHub (fine-grained)

`Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate`:

- **Repository access:** só o repo `databricks_genie` (least privilege).
- **Permissions:** **Contents: Read and write** (⚠️ *write*, não read-only) +
  **Metadata: Read** (automático/obrigatório).
- Copiar o token (só aparece uma vez).

> **Pegadinha:** a caixa de busca da lista de permissions filtra por texto — "Contents"
> não tem a letra "r", então some se você digitar "r". Busque por "contents".

---

## 4. Vincular o GitHub no Databricks

`Avatar (canto sup. direito) → Settings → Linked accounts`: provider **GitHub**,
username `RoseIFOS`, colar o PAT → **Save**.

---

## 5. Clonar o repo como Git folder no Databricks

`Workspace → Create → Git folder`:

- URL: `https://github.com/RoseIFOS/databricks_genie.git`

Resultado: a **máquina local** e o **workspace** viram duas cópias de trabalho do mesmo
repo, tendo o **GitHub como fonte única da verdade**.

---

## 6. Apontar a pipeline Silver pra ler da Git folder

Pipeline Silver → **Settings → Source code paths** → trocar o caminho antigo
(`.../bronze_to_silver/transformations`) por:

```
/Workspace/Users/roseaneinacio@nw5y.onmicrosoft.com/databricks_genie/transformations/silver
```

Validação do run: `customer 701 / account 35 / account_header 10`, todas
**"Full recompute"** (confirma que são Materialized Views, recomputando do snapshot do
Bronze) e **0 linhas dropadas** nas expectations.

---

## 7. Trazer os notebooks de ingestão pro versionamento

- Apaguei a pasta redundante `bronze_to_silver` (a pipeline não lia mais dela).
- Na Git folder: **Create → Folder → `ingestion`**.
- **Move** dos 3 notebooks (`0.Setup`, `1.Control_Ingestion`, `2.Landing_to_bronze`)
  para `databricks_genie/ingestion/`.
- **Commit & Push pela UI do Databricks** (botão do branch `main` → mensagem →
  Commit & Push).

---

## 8. Editar na cópia local e sincronizar (a disciplina das 2 cópias)

Editei um doc **localmente**, mas o remote estava à frente (o commit da ingestão veio do
workspace). Fluxo correto:

```bash
git add PLANO_DATABRICKS_GENIE.md
git commit -m "docs: PLANO — versionamento sobe pra Fase 0"

git pull --rebase origin main   # traz o commit do workspace, reaplica os seus por cima
git push
```

**Pegadinha que apareceu:** `error: cannot pull with rebase: You have unstaged changes`.
O `--rebase` não roda com mudanças pendentes no working tree. Diagnóstico e correção:

```bash
git status                      # achou .gitignore modificado + docs/ untracked
git add .gitignore docs         # o .gitignore ja exclui os PDFs sozinho
git status                      # CONFERIR: nenhum PDF (manual_azure_antigo) staged
git commit -m "docs: versiona manuais markdown; ignora PDFs com credenciais"
git pull --rebase origin main
git push
```

---

## Conceitos-chave (o "porquê")

| Conceito | Resumo |
|---|---|
| **Repo próprio vs pai** | Cada projeto = 1 repo. Nunca commitar dentro de um repo pai com remote errado. |
| **`.gitignore` primeiro** | Segredos (`.env`, PDFs com credencial) fora do versionamento **antes** do 1º commit. |
| **PAT fine-grained** | Escopo mínimo: só o repo, só **Contents R/W**. |
| **Git folders = 2 cópias** | GitHub é a fonte única. `git pull` **antes** de mexer local; `pull --rebase` mantém histórico linear. |
| **Commitar ≠ deploy** | Versionar código é dia 1 (Git folders). `bundle deploy` (dev→prd) é Fase 10. |

---

## Comandos git usados (referência rápida)

```bash
git rev-parse --show-toplevel        # descobrir a raiz do repo atual
git remote -v                        # ver os remotes
git ls-files                         # listar arquivos rastreados
git init -b main                     # criar repo novo com branch main
git status                           # ver estado do working tree
git add <path>                       # colocar em staging
git rm -r --cached <path>            # tirar do staging SEM apagar do disco
git commit -m "msg"                  # commitar o staged
git remote add origin <url>          # conectar ao GitHub
git push -u origin main              # 1o push + vincular upstream
git pull --rebase origin main        # trazer remoto reaplicando commits locais por cima
git push                             # subir commits
```
