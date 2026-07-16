# RUNBOOK — Fase 9 · Observabilidade & FinOps (nativo, sobre system tables)

> Estado e passo-a-passo do pilar de observabilidade/FinOps. Tudo nativo do Databricks
> (system tables + features), sem stack externa. Complementa `docs/manual_azure_novo/
> 06_compute_e_custo.md` (princípios) com o COMO executar.

## Estado (2026-07-16)
- ✅ System schemas habilitados no metastore (`billing`, `access`, `query`, ...).
- ✅ FinOps validado: consumo por **produto de billing** e por **tag** (`system.billing.usage`).
- ✅ Custo **monetário** (join com `system.billing.list_prices`).
- ✅ Observabilidade validada: `system.query.history` (queries do Genie/app, latência, autor).
- ✅ Dashboard AI/BI montado (auto-gerado pelo Genie).

## Pré-requisito que trava todo mundo: ADMIN de CONTA

As system tables (`system.billing`, `system.query`, ...) **não vêm ligadas** e **não são
workspace-level**. Habilitar exige **account admin** (não basta workspace admin).

**Gotcha de auth do CLI:** logar via `--host <workspace>` NÃO carrega contexto de conta.
Para operações de conta, autentique no **account console**:
```bash
databricks auth login --host https://accounts.azuredatabricks.net --account-id <ACCOUNT_ID> --profile <acct>
databricks metastores summary --profile <acct>          # pega o metastore_id
databricks system-schemas list <METASTORE_ID> --profile <acct>
databricks system-schemas enable <METASTORE_ID> billing --profile <acct>
databricks system-schemas enable <METASTORE_ID> access  --profile <acct>
databricks system-schemas enable <METASTORE_ID> query   --profile <acct>
```
> Erro "User is not an account admin for Account" = você é workspace admin, não account
> admin, OU o CLI está no contexto de workspace. Confira o papel em `accounts.azuredatabricks.net`
> → User management, e re-autentique no nível de conta.

## As 3 queries (base do dashboard)

**1. FinOps — custo MONETÁRIO por produto** (quantidade × preço de tabela):
```sql
SELECT u.billing_origin_product,
       round(SUM(u.usage_quantity * p.pricing.default), 2) AS custo_usd
FROM system.billing.usage u
JOIN system.billing.list_prices p
  ON  u.sku_name = p.sku_name
  AND u.usage_start_time >= p.price_start_time
  AND (u.usage_end_time <= p.price_end_time OR p.price_end_time IS NULL)
WHERE u.usage_date >= current_date() - INTERVAL 30 DAYS
GROUP BY u.billing_origin_product
ORDER BY custo_usd DESC;
```
`custo_usd` é **list price em USD** (fatura real varia com desconto de contrato).

**1b. Atribuição por domínio** (usa as tags `projeto`/`dominio` dos jobs/app):
```sql
SELECT custom_tags['dominio'] AS dominio, round(SUM(usage_quantity),4) AS qtd
FROM system.billing.usage
WHERE usage_date >= current_date() - INTERVAL 30 DAYS
GROUP BY custom_tags['dominio'];
```
> Uso interativo (SQL Editor) vem com `custom_tags = {}` — tag só existe em recurso
> tagueado (job/app). É POR ISSO que taguear resources importa.

**2. Observabilidade — volume de queries por dia:**
```sql
SELECT date(start_time) AS dia, count(*) AS queries
FROM system.query.history
WHERE start_time >= current_date() - INTERVAL 30 DAYS
GROUP BY date(start_time) ORDER BY dia;
```

**3. Observabilidade — latência e top usuários:**
```sql
SELECT executed_by, count(*) AS queries,
       round(avg(total_duration_ms)/1000, 1) AS media_seg
FROM system.query.history
WHERE start_time >= current_date() - INTERVAL 30 DAYS
GROUP BY executed_by ORDER BY queries DESC;
```

## Dashboard
- New → Dashboard → aba **Data** (cola as queries como datasets) → **Canvas** (bar p/ custo,
  line p/ queries/dia, table p/ latência) → **Publish**. Ou deixe o **Genie gerar** sozinho.
- Sempre selecionar um **SQL Warehouse serverless** no dashboard (senão "unable to render").

## FinOps — reduzir gasto (importante em cartão pessoal)
- **Parar o app** quando não usar: `databricks apps stop hpn-bi-chat-dev` (compute always-on).
- **Auto-stop curto** nos SQL Warehouses; encerrar clusters interativos ociosos.
- `mode: development` no bundle **pausa schedules** (o job não dispara sozinho).
- **NÃO ligar Model Serving** always-on (decisão da Fase 6: consumo por tabela).
- `databricks bundle destroy -t dev` remove tudo que o bundle criou (tear-down total).

## Outros pilares (nativos, ainda não explorados — projeto real)
- **Budgets** (account console, account admin) — alerta de gasto por cost center.
- **Lakehouse Monitoring** nas tabelas gold/ML — drift e qualidade.
- **MLflow Tracing** no app/modelos — latência e traços (depende do app de pé).
- **system.access.audit** — trilha de auditoria (quem consultou o quê).
- **UC Lineage** — linhagem gold → metric view → Genie → app (Catalog Explorer).
