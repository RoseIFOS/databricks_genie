"""
[ALTERNATIVA] BI Conversacional HPN — versão Streamlit.

⚠️ NÃO é o frontend principal. O principal é React + FastAPI (../main.py).
Mantida aqui como opção de prototipagem rápida. Para usá-la, aponte o command
do Databricks App para alt_streamlit/app.yaml.

Reutiliza os MESMOS módulos compartilhados do diretório app/ (genie_client,
serving, lakebase) — por isso o ajuste de sys.path abaixo.
"""
from __future__ import annotations

import os
import sys

# Permite importar os módulos compartilhados que estão em ../ (app/).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pandas as pd
import plotly.express as px
import streamlit as st

from genie_client import GenieClient
import serving
import lakebase

st.set_page_config(page_title="HPN • BI Conversacional", page_icon="📊", layout="wide")


def get_user_token() -> str | None:
    try:
        return st.context.headers.get("x-forwarded-access-token")
    except Exception:  # noqa: BLE001
        return None


def get_user_email() -> str:
    try:
        return st.context.headers.get("x-forwarded-email", "desconhecido")
    except Exception:  # noqa: BLE001
        return "desconhecido"


DOMAINS = {
    "Comercial":  {"space": os.environ.get("GENIE_SPACE_COMERCIAL"),  "icon": "🛒"},
    "Financeiro": {"space": os.environ.get("GENIE_SPACE_FINANCEIRO"), "icon": "💰"},
}


def render_dataframe(df: pd.DataFrame) -> None:
    if df is None or df.empty:
        return
    st.dataframe(df, use_container_width=True)
    num_cols = df.select_dtypes("number").columns.tolist()
    cat_cols = [c for c in df.columns if c not in num_cols]
    if num_cols and cat_cols and len(df) <= 200:
        x, y = cat_cols[0], num_cols[0]
        st.plotly_chart(px.bar(df, x=x, y=y, title=f"{y} por {x}"), use_container_width=True)


def render_advanced(intent: str) -> None:
    with st.spinner(f"Executando análise: {intent}..."):
        if intent == "forecast":
            out = serving.forecast_sales()
        elif intent == "causal":
            out = serving.causal_drivers()
        else:
            out = serving.recommend()
    st.info(f"🔎 Análise **{intent}**")
    st.json(out)


def chat_tab(domain: str) -> None:
    cfg = DOMAINS[domain]
    state_key, hist_key = f"conv_{domain}", f"hist_{domain}"
    st.session_state.setdefault(state_key, None)
    st.session_state.setdefault(hist_key, [])

    for m in st.session_state[hist_key]:
        with st.chat_message(m["role"]):
            st.markdown(m["content"])
            if m.get("df") is not None:
                render_dataframe(m["df"])

    prompt = st.chat_input(f"Pergunte aos dados de {domain}...")
    if not prompt:
        return

    st.session_state[hist_key].append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    client = GenieClient(cfg["space"], user_token=get_user_token())
    with st.chat_message("assistant"):
        with st.spinner("Consultando o Genie..."):
            ans = client.ask(prompt, conversation_id=st.session_state[state_key])
        if ans.error:
            st.error(f"Erro: {ans.error}")
            return
        st.session_state[state_key] = ans.conversation_id
        st.markdown(ans.text or "_(sem resposta textual)_")
        render_dataframe(ans.dataframe)
        if ans.sql:
            with st.expander("SQL gerado"):
                st.code(ans.sql, language="sql")
        intent = serving.detect_intent(prompt)
        if intent:
            render_advanced(intent)

    st.session_state[hist_key].append(
        {"role": "assistant", "content": ans.text, "df": ans.dataframe}
    )


st.title("📊 HPN • BI Conversacional (Streamlit — alternativa)")
st.caption(f"Usuário: {get_user_email()}")
tabs = st.tabs([f"{DOMAINS[d]['icon']} {d}" for d in DOMAINS])
for tab, domain in zip(tabs, DOMAINS):
    with tab:
        chat_tab(domain)
