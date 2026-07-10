# app — Databricks App (React + FastAPI)

Frontend **principal**: React (Vite + TypeScript). Backend: FastAPI, que também
serve o build do React. Streamlit fica como alternativa em `alt_streamlit/`.

## Estrutura

```
app/
├── app.yaml            # runtime do Databricks App (command: python main.py)
├── requirements.txt    # deps do backend (fastapi, uvicorn, sdk, pandas, psycopg)
├── main.py             # FastAPI: rotas /api/* + serve o React (frontend/dist)
├── genie_client.py     # COMPARTILHADO — wrapper Genie Conversation API (+OBO)
├── serving.py          # COMPARTILHADO — forecast/causal/reco (Model Serving)
├── lakebase.py         # COMPARTILHADO — persistência de conversas/feedback
├── frontend/           # React (Vite + TS)
│   ├── package.json / vite.config.ts / tsconfig.json / index.html
│   └── src/
│       ├── main.tsx           # bootstrap do React
│       ├── App.tsx            # cabeçalho + abas Comercial/Financeiro
│       ├── api.ts             # chamadas para /api/*
│       ├── styles.css         # estilo base (troque pelo design system BIX)
│       └── components/ChatPanel.tsx  # chat + tabela + SQL + feedback
└── alt_streamlit/      # ALTERNATIVA (Streamlit) — não é o principal
```

Os 3 módulos `.py` compartilhados são usados tanto pelo FastAPI quanto pela
versão Streamlit.

## Desenvolvimento local (dois terminais)

```bash
# Terminal 1 — backend (porta 8000)
cd app
pip install -r requirements.txt
python main.py

# Terminal 2 — frontend com hot reload (porta 5173, proxy /api -> 8000)
cd app/frontend
npm install
npm run dev
# abra http://localhost:5173
```

## Build para produção (antes do deploy)

```bash
cd app/frontend
npm ci
npm run build        # gera frontend/dist, que o FastAPI serve em '/'
```

Depois, o deploy é feito pelo Asset Bundle (ver `../GUIA_ASSET_BUNDLE.md`):
```bash
cd ..                # volta para databricks_genie/
databricks bundle deploy -t dev
```

## Notas

- **OBO/RLS:** o `main.py` lê `x-forwarded-access-token` a cada request e repassa
  ao Genie — as consultas herdam a RLS do usuário logado.
- **Gráficos:** o esqueleto renderiza tabela. Para gráficos, plugue uma lib React
  (ex.: `react-plotly.js` ou Recharts, como no `frontend/` de referência).
- **Design:** `styles.css` é mínimo de propósito. Reaproveite shadcn/ui + Tailwind
  do frontend de referência para o visual final.
- **CI/CD:** o build do React (`npm run build`) deve rodar no pipeline antes do
  `bundle deploy -t prd`.
