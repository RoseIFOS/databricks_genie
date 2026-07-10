# alt_streamlit — versão alternativa (Streamlit)

> ⚠️ **Não é o frontend principal.** O principal é **React + FastAPI** (`../main.py`
> + `../frontend/`). Esta versão existe só como opção de prototipagem rápida.
> Na BIX, Streamlit é vetado para arquitetura de referência — use o React.

## Quando usaria isto
- Um protótipo interno descartável, para validar uma pergunta no Genie sem buildar React.

## Como rodar localmente
```bash
cd app/alt_streamlit
pip install -r requirements.txt
streamlit run app.py
```

## Como implantar como Databricks App (se um dia precisar)
Aponte o `source_code_path` (em `../../resources/app.yml`) para esta pasta, ou
copie o `command` de `app.yaml` daqui para o `app.yaml` principal.

Reutiliza os módulos compartilhados de `../` (genie_client, serving, lakebase)
via ajuste de `sys.path` no topo de `app.py`.
