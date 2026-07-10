# Manual Azure + Databricks — pipeline até o DW (versão 2025)

> Reescrita modernizada do manual em [`../manual_azure_antigo/`](../manual_azure_antigo/).
> Mesmo caso de negócio (Olist / fontes OLTP → Lakehouse medallion), mas com as
> features atuais do Databricks. O manual antigo continua na pasta ao lado como
> referência histórica (e como material de "de → para" para entrevista).
>
> Este manual cobre o **como fazer** das **Fases 0–2** do
> [PLANO_DATABRICKS_GENIE.md](../../PLANO_DATABRICKS_GENIE.md) — da infra até o
> DW gold em Unity Catalog. Dali, a camada semântica ([`../../semantic/`](../../semantic/))
> e o Genie assumem.

---

## O que mudou (resumo executivo)

| Tema | Manual antigo (~2021-23) | Este manual (2025) | Onde |
|---|---|---|---|
| Governança | `hive_metastore` + `CREATE DATABASE` | **Unity Catalog** (catálogo → schema → tabela) | [01](01_fundacao_unity_catalog.md) |
| Acesso ao storage | `dbutils.fs.mount` + OAuth com service principal no notebook | **Access Connector** (managed identity) → Storage Credential → External Location + **Volumes** | [02](02_governanca_storage.md) |
| Secrets | Key Vault p/ autenticar o storage | Storage **não usa mais secret**; Key Vault só p/ credenciais de terceiros | [02](02_governanca_storage.md) |
| Ingestão | ADF `Full_Load`, 1 Copy Activity por tabela | **ADF metadata-driven** (baseline) **ou** **Lakeflow Connect** (alvo), ambos incrementais | [03](03_ingestao.md) |
| Transformação | Notebooks imperativos (`read → withColumn → saveAsTable`) | **Lakeflow Declarative Pipelines** em SQL (streaming tables + materialized views + expectations) | [04](04_medallion_lakeflow.md) |
| Orquestração | Rodar notebook na mão / trigger ADF | **Lakeflow Jobs** | [05](05_orquestracao.md) |
| Compute / auth | All-purpose cluster + **PAT token** | **Serverless** + managed identity (sem PAT) | [06](06_compute_e_custo.md) |

---

## Boa prática de credenciais

Nunca versione nem imprima secrets (client_secret, tokens, senhas) em notebooks
ou documentação — use **secret scopes** (Key Vault-backed) e `dbutils.secrets.get()`,
que já retorna `[REDACTED]`. Melhor ainda: na arquitetura nova o acesso ao storage
**não usa secret** — é a managed identity do Access Connector
(capítulo [02](02_governanca_storage.md)).

---

## Ordem de leitura

1. [Fundação & Unity Catalog](01_fundacao_unity_catalog.md)
2. [Governança de storage (External Locations + Volumes)](02_governanca_storage.md)
3. [Ingestão (ADF metadata-driven + Lakeflow Connect)](03_ingestao.md)
4. [Medallion com Lakeflow Declarative Pipelines](04_medallion_lakeflow.md)
5. [Orquestração com Lakeflow Jobs](05_orquestracao.md)
6. [Compute serverless & FinOps](06_compute_e_custo.md)

## Nomenclatura Lakeflow (o que mudou de nome)

- **Lakeflow Connect** = ingestão gerenciada (conectores).
- **Lakeflow Declarative Pipelines** = o antigo **DLT (Delta Live Tables)**.
- **Lakeflow Jobs** = o antigo **Workflows**.
