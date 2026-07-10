"""
BI Conversacional HPN — Backend FastAPI (frontend principal: React).

Responsabilidades:
  1) Rotas /api/*  -> chamam Genie, Model Serving e LakeBase (lógica compartilhada
     em genie_client.py / serving.py / lakebase.py — os MESMOS módulos que a
     versão Streamlit alternativa usa).
  2) Servir o build estático do React (frontend/dist) para o navegador.

Por que FastAPI + React (e não Streamlit):
  - separa front (React/TS) do back (Python), com cara de produto;
  - reaproveita componentes React;
  - mantém a autenticação SSO e o OBO nativos do Databricks Apps (lemos o token
    do usuário no header 'x-forwarded-access-token' a cada request).
"""
from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from genie_client import GenieClient
import serving
import lakebase

app = FastAPI(title="HPN • BI Conversacional")

# Mapeia o domínio (aba do front) para o Genie Space correspondente.
SPACES = {
    "comercial":  os.environ.get("GENIE_SPACE_COMERCIAL"),
    "financeiro": os.environ.get("GENIE_SPACE_FINANCEIRO"),
}


# --------------------------------------------------------------------------- #
# Helpers de identidade (OBO / RLS). Em Databricks Apps o token e o e-mail do
# usuário chegam nos headers a cada requisição.
# --------------------------------------------------------------------------- #
def user_token(request: Request) -> str | None:
    return request.headers.get("x-forwarded-access-token")


def user_email(request: Request) -> str:
    return request.headers.get("x-forwarded-email", "desconhecido")


# --------------------------------------------------------------------------- #
# Contratos de entrada/saída (Pydantic valida o JSON automaticamente).
# --------------------------------------------------------------------------- #
class ChatIn(BaseModel):
    domain: str                       # 'comercial' | 'financeiro'
    question: str
    conversation_id: str | None = None


class FeedbackIn(BaseModel):
    message_id: int
    rating: int                       # +1 / -1


# --------------------------------------------------------------------------- #
# ROTAS DE API
# --------------------------------------------------------------------------- #
@app.get("/api/me")
def me(request: Request):
    """Devolve quem está logado (o front mostra no cabeçalho)."""
    return {"email": user_email(request)}


@app.post("/api/chat")
def chat(body: ChatIn, request: Request):
    """Fluxo principal: pergunta -> Genie -> (opcional) análise avançada -> persiste."""
    space = SPACES.get(body.domain)
    if not space:
        return {"error": f"Domínio inválido: {body.domain}"}

    # OBO: passamos o token do usuário para o Genie herdar a RLS dele.
    client = GenieClient(space, user_token=user_token(request))
    ans = client.ask(body.question, conversation_id=body.conversation_id)
    if ans.error:
        return {"error": ans.error}

    # Converte o DataFrame do resultado em JSON serializável (colunas + linhas).
    columns: list[str] = []
    rows: list[list] = []
    if ans.dataframe is not None and not ans.dataframe.empty:
        columns = list(ans.dataframe.columns)
        clean = ans.dataframe.astype(object).where(ans.dataframe.notna(), None)
        rows = clean.values.tolist()

    # Análise avançada por intenção (forecast/causal/reco) — herda a lógica da Fase 10.
    advanced = None
    intent = serving.detect_intent(body.question)
    if intent:
        advanced = {"intent": intent, "result": _run_advanced(intent)}

    # Persiste a resposta (não-crítico: falha aqui não quebra o chat).
    message_id = None
    try:
        message_id = lakebase.log_message(
            user_email(request), body.domain, "assistant",
            ans.text, ans.sql, ans.conversation_id,
        )
    except Exception:  # noqa: BLE001
        pass

    return {
        "text": ans.text,
        "sql": ans.sql,
        "columns": columns,
        "rows": rows,
        "conversation_id": ans.conversation_id,
        "advanced": advanced,
        "message_id": message_id,
    }


@app.post("/api/feedback")
def feedback(body: FeedbackIn):
    """Registra 👍/👎 (insumo para curar as instruções do Genie)."""
    try:
        lakebase.log_feedback(body.message_id, body.rating)
    except Exception:  # noqa: BLE001
        pass
    return {"ok": True}


def _run_advanced(intent: str) -> dict:
    try:
        if intent == "forecast":
            return serving.forecast_sales()
        if intent == "causal":
            return serving.causal_drivers()
        return serving.recommend()
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}


# --------------------------------------------------------------------------- #
# SERVIR O REACT (build estático). Declarado por ÚLTIMO para não capturar /api.
# Em desenvolvimento você roda o Vite (npm run dev) com proxy para /api; em
# produção o FastAPI serve o conteúdo de frontend/dist.
# --------------------------------------------------------------------------- #
DIST = Path(__file__).parent / "frontend" / "dist"
if DIST.exists():
    app.mount("/assets", StaticFiles(directory=DIST / "assets"), name="assets")

    @app.get("/{full_path:path}")
    def spa(full_path: str):
        # Sempre devolve index.html (SPA cuida do roteamento no cliente).
        return FileResponse(DIST / "index.html")


# --------------------------------------------------------------------------- #
# Entry point. Databricks Apps injeta a porta em DATABRICKS_APP_PORT.
# --------------------------------------------------------------------------- #
if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("DATABRICKS_APP_PORT", os.environ.get("PORT", 8000)))
    uvicorn.run(app, host="0.0.0.0", port=port)
