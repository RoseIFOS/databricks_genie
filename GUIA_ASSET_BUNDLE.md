# Guia — Databricks Asset Bundle (DAB) do zero

Guia de bolso para sua **primeira vez** com Asset Bundles. Você já integrou
Databricks com Git; aqui vai a diferença e o passo a passo.

---

## 1. O modelo mental (2 minutos)

| Você já conhece | Asset Bundle |
|---|---|
| **Git Repos**: sincroniza notebooks/código para o workspace | Sincroniza código **+ cria os recursos** (jobs, apps, schedules, clusters, permissões) |
| Você clica na UI para criar um Job | Você **descreve** o Job em YAML e o `deploy` cria/atualiza |
| Difícil replicar dev → prod igualzinho | O **mesmo** YAML implanta em dev e prod, só mudando o `-t` |

> Resumo: DAB é **Infraestrutura como Código** para o Databricks. O que antes
> você criava clicando, agora vira YAML versionado no Git.

---

## 2. Anatomia deste bundle

```
databricks_genie/               <- RAIZ do bundle (onde está o databricks.yml)
├── databricks.yml              <- identidade + variáveis + ambientes (targets)
├── resources/
│   ├── ml_forecast_job.yml     <- 1 recurso: o Job de forecast
│   └── app.yml                 <- 1 recurso: o Databricks App
├── ml/forecast_sales.py        <- notebook executado pelo Job
├── app/                        <- código do Databricks App
└── semantic/                   <- SQL/metric views (aplicado à parte, ver nota)
```

Hierarquia dos YAML de recurso: `resources` → tipo (`jobs`, `apps`, `pipelines`…)
→ **chave interna** → propriedades. A chave interna é o nome que você usa nos
comandos (`bundle run <chave>`).

---

## 3. Instalação e login (uma vez)

```bash
# Instalar a CLI nova (a antiga "databricks-cli" em pip NÃO serve p/ bundles)
# Windows: winget install Databricks.DatabricksCLI   (ou baixe o binário)
databricks -v          # confirme v0.218 ou superior

# Autenticar no seu workspace Azure Databricks (abre o navegador)
databricks auth login --host https://adb-XXXX.azuredatabricks.net
```

---

## 4. Antes do primeiro deploy — preencha os REPLACE

No `databricks.yml`, troque:
- `host:` → URL do seu workspace (dev e prd).
- `warehouse_id` → ID do SQL Warehouse (pega na UI: SQL Warehouses → seu warehouse → *Connection details* ou na URL).
- `run_as.service_principal_name` (só prd) → Application ID do SP.

---

## 5. Os comandos do dia a dia

```bash
# Sempre rode a partir da pasta databricks_genie/ (onde está o databricks.yml)

# (a) Validar a sintaxe e ver o que será criado
databricks bundle validate -t dev

# (b) Implantar (cria/atualiza os recursos no workspace)
databricks bundle deploy -t dev

# (c) Rodar o job de forecast sob demanda
databricks bundle run forecast_sales_job -t dev

# (d) Ver o resumo do que o bundle implantou
databricks bundle summary -t dev

# (e) Remover tudo que o bundle criou (limpeza)
databricks bundle destroy -t dev
```

Fluxo típico: **editar YAML → validate → deploy → run**. Repetir.

---

## 6. dev vs prd — a parte que mais confunde

- `-t dev` usa `mode: development`:
  - recursos ganham prefixo `[dev seu_usuario]` e ficam **isolados por usuário**
    (duas pessoas podem dar deploy sem se atropelar);
  - **schedules ficam pausados** — o job de forecast NÃO dispara sozinho em dev.
- `-t prd` usa `mode: production`:
  - sem prefixo, schedules **ativos**, roda como o service principal.

> Comece sempre em `dev`. Só promova para `prd` quando validar.

---

## 7. Como isto conversa com o Git (que você já usa)

O bundle vive no Git normalmente. Recomendado:
- **dev**: você dá `deploy` da sua máquina/branch enquanto desenvolve.
- **prd**: um pipeline de **CI/CD** (Azure DevOps ou GitHub Actions) roda
  `databricks bundle deploy -t prd` quando você faz merge na branch principal.
  Assim produção só muda via Git — reproduzível e auditável.

---

## 8. Nota sobre a pasta `semantic/`

Metric views, funções e RLS (SQL) **não** são implantados por este bundle neste
esqueleto — são aplicados como SQL (SQL Editor, notebook ou uma task de job).
Quando quiser, dá para adicionar uma task `sql_task` no bundle que roda esses
arquivos, ou declarar `schemas`/`volumes` como recursos. Deixei fora de propósito
para o primeiro contato com DAB não ficar grande demais.

---

## 9. Erros comuns (e a causa)

| Sintoma | Causa provável |
|---|---|
| `Error: no host configured` | Faltou `host:` no target ou `auth login` |
| `cannot resolve variable ${var.warehouse_id}` | Variável sem `default` e sem valor no target |
| Job não dispara no horário em dev | Esperado: `mode: development` pausa schedules |
| `permission denied` no deploy prd | O SP do `run_as` não tem permissão no workspace/catálogo |
| Notebook não encontrado | `notebook_path` errado (é relativo ao arquivo YAML) |
