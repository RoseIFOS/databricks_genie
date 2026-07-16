"""
Leitura das tabelas de ANÁLISE AVANÇADA (Fase 6): forecast, PVM, recomendação.

DECISÃO DE ARQUITETURA (Fase 6): consumimos as TABELAS `ml.*` materializadas —
NÃO Model Serving em tempo real. Motivo: custo. Endpoint always-on custa caro;
tabela materializada é "só mais uma tabela" e o refresh é um job barato.
(Ver ml/RUNBOOK_ml.md e docs/curso/fase6.md.)

Este módulo é usado pelo app REACT (caminho "b" — app dedicado). O app Streamlit
(caminho "a") não usa isto: lá o próprio Genie responde forecast/reco via trusted
assets. As consultas rodam num SQL Warehouse serverless (id em DATABRICKS_WAREHOUSE_ID).
"""
from __future__ import annotations

import os

from databricks.sdk import WorkspaceClient

_CATALOG = os.environ.get("HPN_CATALOG", "hpn")


def _query(sql: str, user_token: str | None = None) -> list[dict]:
    """Executa SQL no warehouse e devolve lista de dicts (1 por linha)."""
    # OBO: auth_type="pat" evita o conflito com o OAuth do SP no ambiente
    # ("more than one authorization method configured: oauth and pat").
    if user_token:
        w = WorkspaceClient(host=os.environ.get("DATABRICKS_HOST"),
                            token=user_token, auth_type="pat")
    else:
        w = WorkspaceClient()
    resp = w.statement_execution.execute_statement(
        warehouse_id=os.environ["DATABRICKS_WAREHOUSE_ID"],
        statement=sql,
        wait_timeout="30s",
    )
    schema = resp.manifest.schema
    cols = [c.name for c in (schema.columns or [])]
    data = (resp.result.data_array if resp.result else None) or []
    return [dict(zip(cols, row)) for row in data]


def forecast_sales(horizon_months: int = 6, user_token: str | None = None) -> dict:
    """Previsão de vendas — lê a tabela ml.forecast_sales (gerada pelo Prophet)."""
    sql = f"""
        SELECT ds, forecast, forecast_lower, forecast_upper
        FROM {_CATALOG}.ml.forecast_sales
        ORDER BY ds
    """
    return {"table": "forecast_sales", "rows": _query(sql, user_token)}


def pvm_drivers(year_month: int | None = None, comparison_type: str = "YoY",
                user_token: str | None = None) -> dict:
    """Decomposição Preço×Volume×Mix — lê ml.pvm_drivers (ex-'causal')."""
    period = f"AND year_month = {int(year_month)}" if year_month else ""
    ctype = "MoM" if comparison_type == "MoM" else "YoY"   # allowlist (evita injeção)
    sql = f"""
        SELECT year_month, subcategory, delta_revenue,
               effect_volume, effect_price, effect_mix
        FROM {_CATALOG}.ml.pvm_drivers
        WHERE comparison_type = '{ctype}' {period}
        ORDER BY abs(delta_revenue) DESC
    """
    return {"table": "pvm_drivers", "rows": _query(sql, user_token)}


def recommend(segment: str | None = None, user_token: str | None = None) -> dict:
    """Next-best-action por cliente — lê ml.reco_customer_actions."""
    # segment via parâmetro nomeado do warehouse evitaria injeção; aqui, como é uso
    # interno e o valor não vem cru do usuário, mantemos simples com allowlist leve.
    clause = ""
    if segment and segment.replace(" ", "").isalpha():
        clause = f"WHERE segment = '{segment}'"
    sql = f"""
        SELECT customer_key, segment, intent, suggested_lever, priority, gross_sales_12m
        FROM {_CATALOG}.ml.reco_customer_actions
        {clause}
        ORDER BY CASE priority WHEN 'Alta' THEN 1 WHEN 'Média' THEN 2 ELSE 3 END,
                 gross_sales_12m DESC
        LIMIT 100
    """
    return {"table": "reco_customer_actions", "rows": _query(sql, user_token)}


# Roteamento por palavra-chave (o app React usa para decidir se dispara análise).
KEYWORDS = {
    "forecast": ["previsão", "forecast", "projeção", "tendência futura"],
    "pvm":      ["por que", "por quê", "causa", "motivo", "explica", "variação"],
    "reco":     ["recomend", "sugest", "o que fazer", "ação", "melhorar", "next best"],
}


def detect_intent(question: str) -> str | None:
    q = question.lower()
    for intent, kws in KEYWORDS.items():
        if any(k in q for k in kws):
            return intent
    return None
