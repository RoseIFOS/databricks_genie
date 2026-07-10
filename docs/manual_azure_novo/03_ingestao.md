# 03 — Ingestão (fonte OLTP → landing)

> Substitui: *"Datafctory_FullIngestion"* + os Linked Services de
> *"Criando Recursos na Azure"*.

O manual antigo tinha um pipeline `Full_Load` com **uma Copy Activity por tabela**
e **só full load**. Isso não escala (cada tabela nova = nova atividade) e
reprocessa tudo sempre. Aqui documentamos **dois caminhos**:

- **A) ADF metadata-driven** — evolução do que você já tem; mantém o ADF.
- **B) Lakeflow Connect** — ingestão gerenciada dentro do Databricks (alvo).

Escolha um. A tabela abaixo ajuda a decidir.

| Critério | A) ADF metadata-driven | B) Lakeflow Connect |
|---|---|---|
| Onde roda | Azure Data Factory | Databricks (nativo) |
| Peças a manter | ADF + linked services + control table | Só o connector/pipeline |
| Incremental/CDC | Você implementa (watermark) | Nativo (CDC gerenciado) |
| Cobertura de fontes | Qualquer coisa que o ADF conecta | Depende do connector disponível na região — **validar** |
| Quando usar | Fontes on-prem/SaaS heterogêneas; já domina ADF | Fonte suportada; quer menos peças |

> Recomendação: comece por **A** (baixo risco, você já conhece), e migre para
> **B** onde houver connector — reduz manutenção e ganha CDC de graça.

---

## A) ADF metadata-driven (baseline)

Em vez de N atividades, **1 pipeline parametrizado** que itera sobre uma lista de
tabelas.

### Autenticação (mudança importante)
No antigo, o Linked Service do Databricks usava **PAT token**. Troque por
**Managed Identity** (system-assigned do ADF) — sem token de longa duração:
- Linked Service Databricks → *Authentication type*: **Managed Service Identity**.
- Conceda ao MI do ADF o papel adequado no workspace Databricks.
Para o ADLS, o Linked Service pode usar a própria managed identity também.

### Estrutura do pipeline
1. **Control table** (numa Azure SQL ou até num arquivo) listando as tabelas a
   carregar e a coluna de watermark:

   | schema | table | watermark_column | last_loaded_value |
   |---|---|---|---|
   | dbo | olist_customers_dataset | updated_at | 2025-01-01 |
   | dbo | olist_orders_dataset | order_purchase_ts | 2025-01-01 |

2. **Lookup** → lê a control table.
3. **ForEach** (sobre o resultado do Lookup) → dentro dele, **Copy Activity**:
   - Source: dataset parametrizado (`@item().schema`, `@item().table`) com query
     incremental:
     ```sql
     SELECT * FROM @{item().schema}.@{item().table}
     WHERE @{item().watermark_column} > '@{item().last_loaded_value}'
     ```
   - Sink: Parquet no Volume/landing, nome dinâmico (como no antigo):
     `@concat(item().schema, '_', item().table, '.parquet')`
4. **Stored proc / atividade** → atualiza `last_loaded_value` na control table.

Assim, **adicionar uma tabela = uma linha na control table**, não um novo desenho
no pipeline. O `Full_Load` original vira o caso especial "primeira carga".

---

## B) Lakeflow Connect (alvo)

Ingestão gerenciada, definida no próprio Databricks, com CDC.

1. **Catalog / Data Ingestion → Create ingestion pipeline** (ou via connector UI).
2. Configure a **connection** para a fonte (ex.: SQL Server / Postgres) — a
   credencial vai num **secret scope** (aqui o Key Vault ainda entra, cap. 02).
3. Selecione as tabelas de origem e o **destino em UC** (`hpn_dev.bronze`).
4. O connector gerencia snapshot inicial + **CDC incremental** e agenda o refresh.

> **Validar antes:** disponibilidade e o estágio (GA/preview) do connector para a
> sua fonte **na região Azure escolhida**. Se não houver connector para a fonte,
> fique no caminho A.

Vantagem: elimina control table, watermark manual e boa parte do ADF — a
ingestão passa a ser mais um recurso governado do UC (com lineage).

---

## Onde os dados caem
Nos dois caminhos, o destino da landing é o **Volume** do capítulo 02
(`/Volumes/hpn_dev/bronze/landing/`) ou direto uma tabela `hpn_dev.bronze.*`
(caso B). O capítulo [04](04_medallion_lakeflow.md) transforma a partir daí.

## Checklist de saída
- [ ] Caminho escolhido (A ou B) e autenticação **sem PAT**.
- [ ] Carga **incremental** funcionando (não só full).
- [ ] Dados aterrissando no Volume/landing ou em `hpn_dev.bronze`.
