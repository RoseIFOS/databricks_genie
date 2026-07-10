# 01 — Fundação & Unity Catalog

> Substitui: *"Criando Recursos na Azure"* + a parte de `CREATE DATABASE ... hive_metastore`
> de *"Processamento com Databricks"*.

## O que muda em relação ao antigo

No manual antigo você criava RG + ADF + Databricks + ADLS e caía direto no
`hive_metastore`. **O `hive_metastore` é um catálogo por workspace, sem lineage,
sem tags, sem RLS e com namespace de 2 níveis (`database.table`).**

Agora a peça central é o **Unity Catalog (UC)**: um metastore **por região**,
compartilhado entre workspaces, com namespace de **3 níveis**
(`catálogo.schema.tabela`), lineage automático, tags, RLS e column masks. É
pré-requisito do Genie e da RLS que o projeto usa (Fases 3–5 do plano).

## Recursos a provisionar

| Recurso | Observação vs. antigo |
|---|---|
| Resource Group (`rg-hpn-analytics`) | igual |
| **ADLS Gen2** com *hierarchical namespace* | igual — containers `landing`, `bronze` (opcional), `checkpoints` |
| **Azure Databricks (Premium)** | Premium é obrigatório p/ UC, RLS e Genie |
| **Access Connector for Azure Databricks** | **NOVO** — managed identity que substitui o App Registration + client_secret |
| **Unity Catalog Metastore** | **NOVO** — criar na região e **anexar** ao workspace |
| SQL Warehouse **serverless** | ver [capítulo 06](06_compute_e_custo.md) |

> **App Registration + client_secret não são mais necessários** para o acesso ao
> storage. Quem autentica o Databricks no ADLS agora é o Access Connector
> (capítulo [02](02_governanca_storage.md)). App Registration só se você ainda
> precisar de um service principal para *outra* integração.

## Passo a passo

### 1. Metastore UC
Se o workspace já não tiver um metastore anexado:
1. **Azure Databricks Account Console** (`accounts.azuredatabricks.net`) → **Catalog** → **Create metastore**.
2. Região = a mesma do workspace. Aponte para um container ADLS de metadados (ou deixe sem storage raiz e use storage por catálogo).
3. **Assign** o metastore ao seu workspace.

### 2. Estrutura de catálogos e schemas
Um catálogo por ambiente, schemas por camada. Rode no SQL Editor / notebook:

```sql
-- Ambiente de desenvolvimento
CREATE CATALOG IF NOT EXISTS hpn_dev;

CREATE SCHEMA IF NOT EXISTS hpn_dev.bronze;
CREATE SCHEMA IF NOT EXISTS hpn_dev.silver;
CREATE SCHEMA IF NOT EXISTS hpn_dev.gold;
CREATE SCHEMA IF NOT EXISTS hpn_dev.semantic;   -- metric views, funções, RLS (Fase 3+)
CREATE SCHEMA IF NOT EXISTS hpn_dev.ml;         -- modelos e previsões (Fase 6)

-- Repita para hpn_prd (produção)
```

> **De → para direto:**
> `hive_metastore.olist_bronze.Customers` → `hpn_dev.bronze.customers`.
> Note que **não usamos mais `LOCATION '/mnt/...'`** na criação — o storage é
> resolvido pelo UC (managed tables) ou por External Location (capítulo 02).

### 3. Identidades e grupos (Entra ID → Databricks)
- Provisione usuários e **grupos** via **SCIM** do Entra ID (`grp_comercial`,
  `grp_financeiro`, `grp_admin`, `grp_regiao_*`). Esses grupos são a base da RLS
  (Fase 4) e do acesso aos Genie Spaces (Fase 5).

## Checklist de saída
- [ ] Metastore UC anexado ao workspace.
- [ ] Catálogos `hpn_dev` / `hpn_prd` com schemas `bronze/silver/gold/semantic/ml`.
- [ ] Access Connector criado (usado no próximo capítulo).
- [ ] Grupos Entra sincronizados via SCIM.
- [ ] **Secret antigo do App Registration revogado.**
