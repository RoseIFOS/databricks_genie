# RUNBOOK — Fase 6 · Análise Avançada (Forecast, Recomendação, Causal)

> Estado e guia da camada de ML/análise avançada. Os 3 entregáveis viram **tabelas
> `ml.*`** que o Genie e o App consomem — análise avançada é "só mais uma tabela".

---

## Modelo mental

Todos os 3 entregáveis seguem o MESMO padrão (o notebook de forecast já demonstra):

```
treina → rastreia no MLflow → registra no Unity Catalog → materializa tabela ml.* → (opcional) Model Serving
```

Ponto-chave: o Genie/App leem a **tabela** materializada, não o modelo em tempo real.
Isso mantém a arquitetura simples e barata. O Model Serving (endpoint) é opcional, só
quando se precisa de inferência sob demanda (ex.: propensão por cliente no app).

| Entregável | Fonte | Tabela de saída | Estado |
|---|---|---|---|
| **Forecast** | histórico de vendas (`3_gold.fct_sales_details`) | `ml.forecast_sales` | ✅ rodou end-to-end (2026-07-16) |
| **Recomendação** | `4_semantic.dim_customer_rfm` (Fase 3.3) | `ml.reco_customer_actions` | ✅ validado (2026-07-16) |
| **PVM** (ex-"Causal") | decomposição de variação (preço×volume×mix) | `ml.pvm_drivers` | ✅ validado (2026-07-16) |

---

## Decisões desta fase

- **Catálogo = `hpn`** (não `hpn_dev`). Todo o dado real (gold/semantic) vive em `hpn`.
  O bundle foi ajustado (`databricks.yml`: default e dev → `hpn`). A separação
  dev/prd (`hpn_dev`/`hpn_prd`) fica para a Fase 10.
- **Consumo por tabela, não por endpoint** como padrão. Model Serving é opcional.
- **Recomendação começa por regras por segmento** (a decidir na retomada): simples,
  explicável, alinhada ao BI original — antes de partir p/ modelo de propensão.

---

## Passo 1 — Forecast (✅ rodou end-to-end em 2026-07-16)

Primeira execução real num catálogo limpo (`hpn`). O ciclo completo funcionou:
treina → MLflow → registra no UC (`hpn.ml.forecast_sales_model`) → grava tabela
`hpn.ml.forecast_sales`. Bugs de scaffold que a estreia desencavou (todos corrigidos):
`gross_sales` é DECIMAL no gold → `CAST(... AS DOUBLE)`; `CREATE SCHEMA` movido p/ antes
do `register_model`; UC exige `signature` no `log_model` (inferida do in-sample).
Horizonte definido em **14 meses** (histórico termina em nov/2025 → cobre até jan/2027,
i.e. 2026 inteiro); `horizon_months` no job YAML subiu de 6 → 14.

### Realinhamento anterior (2026-07-15)

O scaffold `ml/forecast_sales.py` existia mas estava STALE (escrito antes dos nomes se
firmarem). Correções aplicadas:

1. **Schema:** `{CATALOG}.gold.fct_sales_details` → `` {CATALOG}.`3_gold`.fct_sales_details ``
   (dígito inicial exige backtick).
2. **Coluna:** `SUM(order_quantity * unit_price)` → `SUM(gross_sales)` (coluna canônica
   do gold, igual à measure Gross Sales da metric view).
3. **Colisão no Unity Catalog:** modelo registrado e tabela COMPARTILHAM o namespace do
   schema — não podem ter o mesmo nome. Modelo → `ml.forecast_sales_model`; tabela →
   `ml.forecast_sales`.
4. Widget `catalog` default → `hpn`.

Não precisaram mudar:
- `resources/ml_forecast_job.yml` — já usa `${var.catalog}`, herda `hpn`.
- `app/serving.py` — chama endpoints por env var (`SERVING_FORECAST`...), desacoplado do
  nome do modelo.

**Como executar/validar (no Databricks):**
- Manual: abrir o notebook num cluster ML e rodar célula a célula (Shift+Enter).
- Via bundle: `databricks bundle deploy -t dev` e depois
  `databricks bundle run forecast_sales_job -t dev`.
- Teste-âncora: a célula 2 (carregar histórico) retornar os meses de vendas prova que o
  `3_gold.fct_sales_details` está acessível no catálogo `hpn`.
- Depois: cadastrar `ml.forecast_sales` como trusted asset no Genie Comercial.

---

## Passo 2 — Recomendação (✅ validado — 2026-07-16)

`ml/reco_customer_actions.ipynb`: regras por segmento sobre `dim_customer_rfm` (SEM ML novo,
decidido). Grava `ml.reco_customer_actions`, 1 linha/cliente. Validado: check `intent IS
NULL` = 0 (cobre os 11 segmentos). Decisões:
- **Nicho importa:** HPN = Heavy Power Nutrition (loja de SUPLEMENTOS). Suplemento é
  consumível de reposição (~1 mês/pote) → `recency_days` é sinal de RECOMPRA/lapso e
  recorrência/assinatura é jogada central (o oposto de bem durável).
- **Duas camadas na ação:** `intent` (intenção estratégica — reter/reconquistar/reengajar/
  nutrir; vale em qualquer nicho) + `suggested_lever` (tática fit-suplemento). Assim a
  parte que pode estar errada (tática) fica separada da que é sempre certa (intenção).
- **Ressalva honesta:** o site não tem assinatura nem fidelidade hoje → táticas VIP/
  assinatura são CAPACIDADES A CRIAR, sinalizado no `rationale`.
- **Prioridade (b) = segmento + valor:** parte da prioridade-base do segmento e sobe 1
  nível se o cliente é de alto valor (score `m >= 4` ⇒ `gross_sales_12m >= 200k`).
- **Cobre os 11 segmentos** que a RFM gera (check: `WHERE intent IS NULL` deve dar 0).

## Passo 3 — PVM (✅ validado — 2026-07-16; ex-"Causal")

`ml/pvm_drivers.ipynb`: decomposição Preço×Volume×Mix da variação de receita. Grava
`ml.pvm_drivers`. Validado: check de fechamento = 0 linhas (soma dos 3 efeitos = variação
real em todo mês); leitura OK (ex.: YoY 202506). **NÃO é ML nem inferência causal** — é
aritmética de decomposição.
Cortamos o DoWhy/EconML (o Genie já responde "onde mexeu"; PVM dá a ele UMA convenção
fixa e correta). Tabela renomeada `causal_drivers` → `pvm_drivers` por honestidade.
Decisões (detalhe completo nas células markdown do notebook):
- **Grão = subcategoria** (`dim_product.subcategory_name`); some p/ categoria/total.
- **Mensal, não cravado:** decompõe todos os meses; `comparison_type` = MoM **e** YoY.
- **"Preço" = preço médio realizado** por subcategoria = receita/quantidade.
- **Mix = RESÍDUO** (`delta − volume − price`) → garante fechamento EXATO na variação de
  receita e absorve subcategoria nova/descontinuada (que não tem preço-base). Trade-off:
  mix vira meio "caixa-preta" (composição + entradas/saídas). Check de fechamento no notebook.
- Colunas exigidas confirmadas no gold: `order_quantity`, `unit_price`, `gross_sales`,
  `product_key`→`dim_product`. `gross_sales` é DECIMAL → CAST DOUBLE (pegadinha do forecast).

> DoWhy/EconML (inferência causal de verdade — contrafactual com confundidores) ficou FORA
> de escopo por decisão da usuária. Se um dia voltar, é um 4º entregável, não parte do PVM.

---

## Referências no repo
- `databricks.yml` — bundle (catálogo, targets dev/prd, variáveis)
- `resources/ml_forecast_job.yml` — Lakeflow Job do forecast (schedule diário 05:00)
- `ml/forecast_sales.py` — notebook Prophet + MLflow + UC
- `ml/reco_customer_actions.ipynb` — recomendação (regras RFM → `ml.reco_customer_actions`)
- `ml/pvm_drivers.ipynb` — decomposição Preço×Volume×Mix (→ `ml.pvm_drivers`)
- `app/serving.py` — chamadas aos endpoints de serving (Fase 7)
- `GUIA_ASSET_BUNDLE.md` — guia do Asset Bundle
