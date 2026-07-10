# databricks_genie — esqueleto do BI Conversacional (Azure + Databricks)

Materializa as Fases 3, 5, 6 e 7 do [PLANO_DATABRICKS_GENIE](./PLANO_DATABRICKS_GENIE.md).

> **Projeto autocontido.** Tudo do novo projeto vive nesta pasta — é só movê-la
> para um repositório novo. Nada aqui depende do projeto de referência (o chat
> original foi usado só para planejar). A raiz do bundle é este diretório.

## Estrutura

```
databricks_genie/                # << RAIZ do Asset Bundle
├── databricks.yml               # DAB: identidade + variáveis + ambientes (dev/prd)
├── GUIA_ASSET_BUNDLE.md         # tutorial de Asset Bundle (primeira vez)
├── PLANO_DATABRICKS_GENIE.md    # plano completo (10 fases)
├── resources/                   # DAB: definição de cada recurso
│   ├── ml_forecast_job.yml      # Job que roda o notebook de forecast
│   └── app.yml                  # o Databricks App como recurso do bundle
├── ml/                          # Fase 6 — modelos
│   └── forecast_sales.py        # notebook de forecast (Prophet + MLflow + UC)
├── semantic/                    # Fase 3/4 — camada semântica e governança
│   ├── 01_gold_views.sql        # view transacional unificada + comments + tags
│   ├── mv_comercial.yaml        # Metric View comercial (medidas DAX de vendas)
│   ├── mv_financeiro.yaml       # Metric View financeiro (DRE actual/budget)
│   ├── 02_functions.sql         # RFM, segmentos, time-intelligence (YoY/MoM)
│   └── 03_rls.sql               # RLS regional + column mask + grants por domínio
└── app/                         # Fase 7 — Databricks App (React + FastAPI)
    ├── app.yaml                 # runtime do app (command: python main.py)
    ├── requirements.txt         # deps do backend (fastapi/uvicorn/sdk/...)
    ├── main.py                  # FastAPI: rotas /api/* + serve o React
    ├── genie_client.py          # COMPARTILHADO — Genie Conversation API (+OBO/RLS)
    ├── serving.py               # COMPARTILHADO — forecast/causal/reco
    ├── lakebase.py              # COMPARTILHADO — persistência conversas/feedback
    ├── frontend/                # React (Vite + TS): App.tsx, ChatPanel, api.ts
    └── alt_streamlit/           # ALTERNATIVA (Streamlit) — não é o principal
```

> **Frontend:** React + FastAPI é o padrão (Streamlit é vetado na BIX; fica só
> como alternativa de protótipo em `app/alt_streamlit/`). Detalhes de dev/build
> em [app/README.md](./app/README.md).

> ⚠️ Dois arquivos parecidos, papéis diferentes: `app/app.yaml` = como o app
> **roda**; `resources/app.yml` = como o bundle **implanta** o app.

## Ordem de aplicação

1. **Camada semântica** (após o DW gold existir):
   ```sql
   -- Execute no SQL Editor / notebook, na ordem:
   -- 01_gold_views.sql  ->  02_functions.sql  ->  03_rls.sql
   ```
   Crie os Metric Views a partir dos YAMLs (Catalog Explorer > Create Metric View, ou via API/Asset Bundle).

2. **Genie Spaces** (Fase 5): criar 2 Spaces, associar cada Metric View + tabelas do domínio, escrever General Instructions e cadastrar `v_sales_time_intelligence` / `dim_customer_rfm` como trusted assets.

3. **Modelos** (Fase 6): o notebook `ml/forecast_sales.py` treina, registra no
   Unity Catalog e grava as previsões. Ele é executado pelo Job do bundle
   (`resources/ml_forecast_job.yml`). Depois, sirva o modelo via Model Serving.

4. **Deploy via Asset Bundle** (Job + App): leia o
   [GUIA_ASSET_BUNDLE.md](./GUIA_ASSET_BUNDLE.md) e rode, a partir desta pasta:
   ```bash
   databricks bundle validate -t dev
   databricks bundle deploy   -t dev        # cria Job de forecast + App
   databricks bundle run forecast_sales_job -t dev
   ```

## Notas importantes

- **Paridade com o Power BI:** valide cada measure do Metric View contra o número do relatório antes do go-live. Comentários `# DAX:` em cada measure indicam a origem.
- **Segurança herdada:** a RLS do `03_rls.sql` vale para Genie e app automaticamente (nada de guardrail na aplicação).
- **Versões do SDK:** os nomes de método da Genie API (`start_conversation_and_wait`, `get_message_attachment_query_result`) podem variar por versão do `databricks-sdk`; o `genie_client.py` já tem fallback.
- **Net Sales / Returns** dependem da view unificada `gold.v_sales_txn` (evita fanout entre `fSalesDetails` e `fSalesReturns`).
