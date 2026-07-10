"""
Chamadas aos endpoints de Model Serving (Fase 6): forecast, causal, recomendação.
Equivale aos nodes "Fase 10" do projeto original, agora como modelos servidos.
"""
from __future__ import annotations

import os
from databricks.sdk import WorkspaceClient

_w = WorkspaceClient()


def _query(endpoint: str, records: list[dict]) -> dict:
    resp = _w.serving_endpoints.query(name=endpoint, dataframe_records=records)
    # resp.predictions costuma trazer a saída do modelo
    return getattr(resp, "predictions", resp.as_dict())


def forecast_sales(horizon_months: int = 6, region: str | None = None) -> dict:
    """Previsão de vendas (modelo Prophet/AutoML servido)."""
    endpoint = os.environ["SERVING_FORECAST"]
    return _query(endpoint, [{"horizon": horizon_months, "region": region}])


def causal_drivers(metric: str = "gross_margin", period: str | None = None) -> dict:
    """Decomposição/inferência causal dos drivers de uma métrica (preço x volume x mix)."""
    endpoint = os.environ["SERVING_CAUSAL"]
    return _query(endpoint, [{"metric": metric, "period": period}])


def recommend(customer_key: int | None = None, segment: str | None = None) -> dict:
    """Next-best-action por cliente/segmento RFM."""
    endpoint = os.environ["SERVING_RECO"]
    return _query(endpoint, [{"customer_key": customer_key, "segment": segment}])


# Roteamento por palavra-chave (herda a ideia do route_sql_validator da Fase 10)
KEYWORDS = {
    "forecast":  ["previsão", "forecast", "projeção", "tendência futura"],
    "causal":    ["por que", "por quê", "causa", "motivo", "explica"],
    "reco":      ["recomend", "sugest", "o que fazer", "ação", "melhorar"],
}


def detect_intent(question: str) -> str | None:
    q = question.lower()
    for intent, kws in KEYWORDS.items():
        if any(k in q for k in kws):
            return intent
    return None
