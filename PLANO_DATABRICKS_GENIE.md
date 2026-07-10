# Plano de Projeto — BI Conversacional em Azure + Databricks Genie

> **Objetivo:** replicar as capacidades do BI Agent (chat com dados, análise causal, forecast, recomendação, observabilidade/FinOps/governança) usando uma stack Azure + Databricks, com dois Genie Spaces (Comercial e Financeiro) e frontend em Databricks Apps.
>
> **Base de negócio:** modelo semântico do Power BI existente (`docs/power_bi/`), um star schema HPN com domínio Comercial (vendas, clientes, produtos, RFM) e domínio Financeiro (DRE actual vs budget).

---

## 0. Visão de arquitetura (de → para)

| Camada | Projeto original | Novo projeto (Azure + Databricks) |
|---|---|---|
| Ingestão | Scripts / DW pronto | **ADF** (orquestração) → **ADLS Gen2** (landing) / **Lakeflow Connect** |
| Transformação | — | **Lakeflow Declarative Pipelines** (Bronze→Silver→Gold, medallion) |
| Data Warehouse | PostgreSQL | **Delta Lake / Unity Catalog** (gold) + **SQL Warehouse** |
| Camada semântica | Prompts + dicionário de dados | **Unity Catalog**: comentários, tags, **Metric Views**, **funções SQL/UDF** |
| NL → SQL | LangGraph (SQL Writer/Validator + RAG) | **Databricks Genie** (2 Spaces) via Conversation API |
| Análise avançada | Nodes Fase 10 (LLM) | **Jobs/Notebooks + MLflow + Model Serving** (Prophet/AutoML, causal, reco) |
| Cache | Redis + FAISS | **LakeBase** (estado do app) + cache do Genie/Warehouse |
| Estado do app (users, chat, feedback) | PostgreSQL + JWT | **LakeBase** (Postgres gerenciado) + auth nativa do Databricks Apps |
| Frontend | React + FastAPI | **Databricks Apps** com **React + FastAPI** (Streamlit vetado na BIX) |
| Guardrails / acesso | Excel + validators | **Unity Catalog**: row filters, column masks, grants por grupo |
| Observabilidade | LangSmith + logs | **System Tables**, **MLflow Tracing**, **Lakehouse Monitoring**, **AI Gateway** |
| FinOps | Cost tracking custom | **system.billing.usage** + **Budgets** + tags |

**Fluxo em produção:**
```
Fontes → ADF → ADLS (bronze) → Lakeflow (silver/gold em Delta/UC)
       → Metric Views + Funções (camada semântica certificada)
       → Genie Spaces (Comercial / Financeiro)
       → Databricks App (chat + gráficos)
            ├─ Genie Conversation API (texto → SQL → dados)
            ├─ Model Serving (forecast / causal / recomendação)
            └─ LakeBase (histórico de conversas, feedback, prefs)
       → System Tables / MLflow / Monitoring (observabilidade, FinOps, governança)
```

> **Nota de nomenclatura Lakeflow:** *Lakeflow Connect* = ingestão gerenciada; *Lakeflow Declarative Pipelines* = o antigo DLT (transformação declarativa); *Lakeflow Jobs* = o antigo Workflows (orquestração).

---

## Fase 0 — Fundação Azure & Databricks

**Meta:** ambiente provisionado, governança básica e identidades.

- [ ] Criar/validar **Azure Subscription** e Resource Group dedicado (ex: `rg-hpn-analytics`).
- [ ] Provisionar **Azure Databricks Workspace** (Premium — necessário para Unity Catalog, RLS, Genie).
- [ ] Provisionar **ADLS Gen2** (storage account com hierarchical namespace) — containers `landing`, `bronze`, `checkpoints`.
- [ ] Configurar **Unity Catalog Metastore** na região e anexar ao workspace.
- [ ] Criar **Access Connector for Azure Databricks** (managed identity) e conceder `Storage Blob Data Contributor` no ADLS → registrar como **Storage Credential** + **External Location** no UC.
- [ ] Integrar identidade: **Microsoft Entra ID (Azure AD) SCIM** → provisionar usuários e **grupos** no Databricks (ex: `grp_comercial`, `grp_financeiro`, `grp_admin`, `grp_regiao_sul`, etc.).
- [ ] Definir estrutura de **catálogos UC** (por ambiente):
  - `hpn_dev`, `hpn_prd` → schemas `bronze`, `silver`, `gold`, `semantic`, `ml`, `app`.
- [ ] Criar **SQL Warehouse** (serverless recomendado) para Genie e o app. Habilitar auto-stop.
- [ ] Definir política de **tags** obrigatórias (cost center, ambiente, domínio) para FinOps desde o dia 1.
- [ ] **Versionamento desde o dia 1 (NÃO deixar pra depois):** criar **repositório Git próprio** do projeto (GitHub) e conectar o workspace via **Databricks Git folders (Repos)** — GitHub como fonte única da verdade. Todo notebook/SQL/pipeline nasce dentro da Git folder e é commitado conforme avança. Proteger segredos no `.gitignore` (`.env`, notas/PDFs com credenciais).

**Entregável:** workspace governado, UC ativo, grupos Entra sincronizados, **e código sob controle de versão desde o primeiro artefato**.

> **Lição aprendida (corrigida aqui):** versionar é prática de Fase 0, não de Fase 10.
> Construir na UI sem commitar ("clickops") acumula trabalho não-versionado e vira
> dívida. **Git folders resolvem o versionamento no dia 1**; a automação de deploy via
> Asset Bundle (`bundle deploy` dev→prd) é que fica pra Fase 10 — são coisas diferentes.

---

## Fase 1 — Ingestão (ADF → ADLS)

**Meta:** trazer as fontes (ERP/CRM/planilhas HPN) para a landing zone de forma orquestrada.

- [ ] Mapear fontes reais que alimentam o modelo (vendas, retornos, custos, financeiro/DRE, cadastros de cliente/produto).
- [ ] Criar **Azure Data Factory** com **Linked Services** para as fontes e para o ADLS.
- [ ] Modelar **pipelines de cópia** (Copy Activity) → gravar em `landing/<fonte>/<tabela>/<yyyy>/<mm>/<dd>/` (particionado por data de carga).
- [ ] Definir estratégia de carga: full load inicial + **incremental** (watermark por data de modificação).
- [ ] Agendar **Triggers** (tumbling window/schedule) e configurar alertas de falha.
- [ ] (Alternativa/complemento) Avaliar **Lakeflow Connect** para conectores gerenciados (SQL Server, Salesforce, etc.) direto no Databricks, reduzindo ADF onde possível.

**Entregável:** dados crus versionados em ADLS, cargas agendadas e monitoradas.

> **Decisão de arquitetura:** ADF é ótimo para orquestrar extração de fontes on-prem/SaaS heterogêneas. A transformação fica **toda no Databricks** (Lakeflow), não no ADF — evita lógica de negócio espalhada.

---

## Fase 2 — Lakehouse Medallion (Lakeflow + Unity Catalog)

**Meta:** construir o DW em Delta com qualidade e lineage, reproduzindo o star schema do Power BI.

- [ ] Criar **Lakeflow Declarative Pipeline** com as três camadas:
  - **Bronze:** ingestão bruta de `landing` (Auto Loader / `read_files`), schema evolution, sem regra de negócio.
  - **Silver:** limpeza, tipagem, deduplicação, chaves substitutas, **expectations** (`@dlt.expect`) para qualidade.
  - **Gold:** modelo dimensional final (star schema), pronto para consumo.
- [ ] Materializar as tabelas gold espelhando o modelo do PBIP:
  - **Fatos:** `fct_sales_details`, `fct_sales_returns`, `fct_product_cost_history`, `fct_finance`.
  - **Dimensões:** `dim_customer`, `dim_product`, `dim_calendar`, `dim_account`, `dim_account_header`, `dim_organization`, `dim_department_group`.
  - **Auxiliares:** tabela de mapeamento RLS `map_rls_region` (email → região) — substitui `auxRLS`.
- [ ] Definir **Primary/Foreign Keys** no UC (informacional) para lineage e para o Genie entender os joins.
- [ ] Aplicar **expectations** de qualidade (ex: `UnitPrice >= 0`, `Scenario in ('actual','budget')`).
- [ ] Otimizar: **Liquid Clustering** (ou partição) nas fatos por data; `OPTIMIZE`/`VACUUM` agendados via Lakeflow Jobs.
- [ ] Agendar o pipeline (trigger após o ADF concluir a landing).

**Entregável:** DW dimensional em Delta/UC, com qualidade, PK/FK e lineage automático.

---

## Fase 3 — Camada Semântica (o coração do projeto)

**Meta:** dar ao Genie contexto de negócio equivalente às medidas DAX do Power BI. É aqui que a qualidade das respostas é ganha ou perdida.

### 3.1 Documentação (comentários e tags)
- [ ] Adicionar `COMMENT` em **toda tabela e coluna** gold (linguagem de negócio, não técnica).
  ```sql
  COMMENT ON TABLE gold.fct_sales_details IS
    'Detalhe de vendas por item de pedido. Grão: linha de pedido.';
  ALTER TABLE gold.fct_sales_details ALTER COLUMN unit_price
    COMMENT 'Preço unitário de venda em USD';
  ```
- [ ] Aplicar **tags UC** de domínio (`domain=comercial` / `domain=financeiro`) e sensibilidade (`pii`, `financial`).
- [ ] Marcar ativos como **Certified** no Catalog Explorer.

### 3.2 Metric Views (equivalente às medidas DAX)
Metric Views são o padrão moderno de camada semântica no Unity Catalog: definem dimensões e medidas (com agregação) de forma declarativa e versionada, consumíveis por Genie, SQL e BI.

- [ ] Criar **`semantic.mv_comercial`** com as medidas de vendas. Exemplo (YAML da metric view):
  ```yaml
  version: 0.1
  source: gold.fct_sales_details
  joins:
    - name: customer
      source: gold.dim_customer
      on: source.customer_key = customer.customer_key
    - name: product
      source: gold.dim_product
      on: source.product_key = product.product_key
    - name: calendar
      source: gold.dim_calendar
      on: source.order_date = calendar.date_id
  dimensions:
    - name: Ano
      expr: calendar.year
    - name: Cliente
      expr: customer.customer
    - name: Regiao
      expr: customer.region
    - name: Categoria
      expr: product.category_name
  measures:
    - name: Gross Sales
      expr: SUM(order_quantity * unit_price)
    - name: Cost of Sales
      expr: SUM(order_quantity * unit_cost)
    - name: Discounts
      expr: SUM(discount_amount)
    - name: Quantity
      expr: SUM(order_quantity)
    # Net Sales, Gross Margin %, etc. compostas via MEASURE()
  ```
  > Traduza as medidas DAX (`Gross Sales`, `Net Sales`, `Cost of Sales`, `Gross Margin %`, `Discounts`, `Returns`, `% Returns`, `Quantity`, YoY/MoM) para `measures` da metric view.
- [ ] Criar **`semantic.mv_financeiro`** sobre `fct_finance` + `dim_account`/`dim_account_header`:
  - Medidas: `Total Amount Actual` (`SUM(amount * sign) WHERE scenario='actual'`), `Total Amount Budget` (`scenario='budget'`), `Budget Deviation`, `Budget Deviation %`, `% VA`, `% HA`.
  - Dimensões: conta, header da conta (DRE), organização, department group, calendário.
- [ ] Validar cada medida contra o Power BI (paridade de números) antes de liberar.

### 3.3 Funções SQL (lógica reutilizável)
- [ ] Criar **funções UC** para cálculos complexos que o Genie deve reutilizar como "trusted assets":
  ```sql
  CREATE OR REPLACE FUNCTION semantic.rfm_score(customer_key BIGINT)
  RETURNS STRUCT<r INT, f INT, m INT> ...;
  CREATE OR REPLACE FUNCTION semantic.customer_segment(...)  -- Champions, At Risk, Lost...
  RETURNS STRING ...;
  ```
  > A classificação **RFM** e os segmentos de cliente (Champions, Loyal, At Risk, Lost, etc.) do Power BI viram funções/tabelas gold, não lógica no prompt.

**Entregável:** camada semântica certificada, com paridade de números vs Power BI. **Este é o pré-requisito para o Genie funcionar bem.**

---

## Fase 4 — Governança & Segurança (RLS / masking)

**Meta:** reproduzir a RLS regional do Power BI (`[Email] = USERPRINCIPALNAME()`) e o controle por departamento.

- [ ] Criar tabela de mapeamento `semantic.map_rls_region(email STRING, region STRING)` (substitui `auxRLS`).
- [ ] Criar **Row Filter** e aplicar nas fatos/dimensões sensíveis:
  ```sql
  CREATE OR REPLACE FUNCTION semantic.rls_region(region STRING)
  RETURN is_account_group_member('grp_admin')
      OR region IN (
        SELECT region FROM semantic.map_rls_region
        WHERE email = current_user()
      );

  ALTER TABLE gold.dim_customer
    SET ROW FILTER semantic.rls_region ON (region);
  ```
- [ ] Criar **Column Masks** para PII (ex: dados de contato de cliente) por grupo.
- [ ] Definir **GRANTs** por domínio: `grp_comercial` → schema/metric view comercial; `grp_financeiro` → financeiro. Admin vê tudo.
- [ ] Garantir que **Genie herda as permissões UC** — usuário só consulta o que pode ver (segurança no nível de dado, não de prompt).
- [ ] Documentar a matriz de acesso (grupo × domínio × região) — substitui o `access_rules.xlsx`.

**Entregável:** segurança aplicada no dado (UC), herdada automaticamente por Genie e pelo app.

> **Vantagem sobre o original:** no projeto antigo os guardrails eram lógica de aplicação (podia ser burlada por um SQL diferente). Aqui a RLS é do motor — impossível vazar dados de outra região.

---

## Fase 5 — Genie Spaces (Comercial + Financeiro)

**Meta:** dois espaços de chat-com-dados curados.

### 5.1 Genie Space "Comercial"
- [ ] Criar Genie Space, associá-lo ao **SQL Warehouse** serverless.
- [ ] Adicionar como **tabelas/ativos**: `mv_comercial`, fatos e dimensões comerciais, funções RFM.
- [ ] Escrever **General Instructions** (em PT-BR): glossário de negócio, moeda (USD), como formatar valores monetários vs quantidades (herdando a regra do projeto original: COUNT = quantidade, SUM de valor = monetário), definição de "vendas líquidas", período fiscal, etc.
- [ ] Cadastrar **Example SQL queries** (perguntas frequentes → SQL correto) como "trusted assets".
- [ ] Cadastrar **sample questions** e sinônimos (ex: "faturamento" = Gross Sales).
- [ ] Testar com um benchmark de ~30–50 perguntas reais e iterar as instruções.

### 5.2 Genie Space "Financeiro"
- [ ] Repetir com `mv_financeiro`, `fct_finance`, `dim_account*`.
- [ ] Instruções específicas: estrutura da DRE (`account_header`), actual vs budget, sinal contábil (`sign`), regras de subtotal.
- [ ] Restringir acesso ao Space ao `grp_financeiro` + admin.

**Entregável:** dois Genie Spaces validados, cada um restrito ao seu público.

> **Por que dois Spaces:** cada Space tem escopo/instruções próprias → respostas mais precisas e governança de acesso por domínio (comercial não enxerga DRE e vice-versa).

---

## Fase 6 — Análise Avançada (Causal, Forecast, Recomendação)

**Meta:** cobrir os nodes "Fase 10" do original com ML gerenciado no Databricks.

- [ ] **Forecast:**
  - Notebook/Job que treina previsão de vendas/receita (Prophet, statsmodels ou **Databricks AutoML** para forecasting).
  - Registrar modelo no **Unity Catalog (MLflow Model Registry)**; servir via **Model Serving endpoint**.
  - Materializar previsões em `ml.forecast_sales` para o Genie/app consultarem.
- [ ] **Análise Causal:**
  - Job de decomposição de variação (ex: waterfall preço × volume × mix explicando Δ de receita) e/ou inferência causal (`DoWhy`/`EconML`) para drivers de margem.
  - Expor resultado como tabela `ml.causal_drivers` + endpoint opcional.
- [ ] **Recomendação:**
  - Regras/ML sobre segmentos RFM (ex: ação por segmento: reativar "At Risk", upsell em "Champions").
  - Opcional: modelo de propensão (next-best-action) servido via Model Serving.
- [ ] Orquestrar treino/refresh via **Lakeflow Jobs** (schedule + retries + alertas).
- [ ] Rastrear experimentos e métricas no **MLflow**.

**Entregável:** endpoints/tabelas de forecast, causal e recomendação prontos para o app orquestrar.

> **Padrão de integração:** o Genie responde perguntas factuais ("quanto vendemos?"); o **App** decide quando chamar forecast/causal/reco (por palavra-chave ou botão), como o roteamento condicional da Fase 10 fazia no LangGraph.

---

## Fase 7 — Databricks App (frontend de chat)

**Meta:** um app com os dois chats + gráficos + análises, autenticado e governado.

- [ ] Criar **Databricks App** com **React + FastAPI** (Streamlit é vetado na BIX para arquitetura de referência). O FastAPI serve o build do React e as rotas `/api/*`. Frameworks Python de UI (Streamlit/Dash) ficam só como protótipo descartável.
- [ ] Estruturar duas áreas de chat: **Comercial** e **Financeiro** (cada uma aponta para seu Genie Space).
- [ ] Integrar **Genie Conversation API** (`start-conversation` / `create-message` / poll de resultado) via `databricks-sdk`.
- [ ] Renderizar resultados: tabela + **gráfico** (Plotly) a partir do dataframe retornado.
- [ ] Adicionar acionadores para **forecast/causal/recomendação** (chamam Model Serving) e exibir insight + visual.
- [ ] Usar a **identidade do usuário** (OBO — on-behalf-of) para que consultas respeitem a RLS do UC.
- [ ] Configurar recursos do app (SQL Warehouse, Serving endpoints, LakeBase) via app resources/secrets.
- [ ] Deploy do app e teste de autenticação SSO (Entra ID).

**Entregável:** app único, dois chats, com governança de acesso ponta a ponta.

> **Databricks Apps** já provê hosting, autenticação (SSO Databricks/Entra), scaling e isolamento — elimina o FastAPI+JWT+CORS+Docker do projeto original.

---

## Fase 8 — LakeBase (estado operacional do app)

**Meta:** substituir Postgres+Redis para o estado do aplicativo.

- [ ] Provisionar instância **LakeBase** (Postgres OLTP gerenciado do Databricks).
- [ ] Modelar tabelas: `conversations`, `messages`, `feedback` (👍/👎 por resposta), `user_preferences`, `cache_semantico` (opcional).
- [ ] Conectar o app ao LakeBase (baixa latência para leitura/escrita transacional).
- [ ] (Opcional) **Sincronizar** tabelas gold do UC → LakeBase (synced tables) para leituras rápidas no app.
- [ ] Capturar feedback do usuário → alimentar a melhoria das instruções do Genie e avaliação.

**Entregável:** histórico de conversas, feedback e preferências persistidos com baixa latência.

---

## Fase 9 — Observabilidade, FinOps e Governança (expectativa da TI)

**Meta:** o pacote que a TI espera. Tudo nativo, sem stack externa.

### Observabilidade
- [ ] **MLflow Tracing / Agent Evaluation** para o app (latência, qualidade, traços de cada chamada Genie/modelo).
- [ ] **Query History** e **system.query.history** para analisar consultas do Genie/app.
- [ ] **Lakehouse Monitoring** nas tabelas gold e nas saídas de ML (data drift, qualidade).
- [ ] Coletar **feedback do Genie** (avaliações dos usuários) para curadoria contínua.

### FinOps
- [ ] Dashboard sobre **`system.billing.usage`** (DBUs por warehouse, job, app, serving) — custo por domínio via **tags**.
- [ ] Configurar **Budgets** e alertas de gasto por cost center.
- [ ] Auto-stop nos warehouses e right-sizing dos endpoints de serving.
- [ ] (Se usar LLM externo) **AI Gateway** para rate limit, log e controle de custo de tokens.

### Governança
- [ ] **Lineage** end-to-end no UC (ADF→bronze→gold→metric view→Genie→app) — auditável.
- [ ] **system.access.audit** para trilha de auditoria (quem consultou o quê).
- [ ] Catálogo/glossário de negócio documentado; ativos certificados.
- [ ] Revisão periódica de grants e da matriz de acesso.

**Entregável:** painéis de observabilidade, FinOps e trilha de governança operando sobre system tables.

---

## Fase 10 — DataOps / CI-CD / Deploy

**Meta:** promover dev → prd de forma reprodutível.

> **Nota:** o *versionamento do código* já acontece desde a **Fase 0** (Git folders +
> GitHub). Esta fase trata da *automação de deploy/promoção* via Asset Bundle — declarar
> os recursos (jobs, app, pipelines) como código e implantá-los entre ambientes. Não
> confundir "commitar código" (dia 1) com "bundle deploy" (aqui).

- [ ] Declarar os recursos em **Databricks Asset Bundles (DAB)**: jobs, o App, serving endpoints, e (quando quiser) pipelines/metric views. Reconciliar o catálogo do bundle (`hpn_dev`/`hpn_prd`) com o catálogo usado no build interativo (`hpn`).
- [ ] Deploy **manual** via bundle (`databricks bundle deploy -t dev` / `-t prd`) — baseline suficiente para o MVP.
- [ ] Separar ambientes `dev`/`prd` por catálogo UC e por target do bundle.
- [ ] Checklist de go-live: RLS validada, budgets ativos, monitoramento ligado, benchmark de perguntas ≥ meta de acerto.

> **Escopo do MVP:** deploy manual pelo bundle. **Automação de CI/CD e testes de
> regressão são melhoria pós-MVP** (ver seção "Sugestões de melhoria"). Não
> bloqueiam a entrega.

**Entregável:** deploy reprodutível via Asset Bundle (manual), com go-live checado.

---

## Resumo dos entregáveis por fase

| Fase | Entregável-chave |
|---|---|
| 0 | Workspace + UC + grupos Entra |
| 1 | Ingestão ADF → ADLS |
| 2 | DW medallion em Delta/UC (star schema) |
| 3 | **Camada semântica: Metric Views + funções + docs** |
| 4 | RLS/masking no Unity Catalog |
| 5 | 2 Genie Spaces (Comercial + Financeiro) |
| 6 | Forecast + Causal + Recomendação (ML) |
| 7 | Databricks App (2 chats + gráficos) |
| 8 | LakeBase (estado do app) |
| 9 | Observabilidade + FinOps + Governança |
| 10 | Deploy reprodutível via Asset Bundle (manual) |

## Sugestões de melhoria (pós-MVP / opcional)

> Não fazem parte do escopo inicial. Adicionam robustez, mas também complexidade —
> entrar só depois que o MVP estiver de pé e validado.

1. **CI/CD automatizado (GitHub Actions / Azure DevOps).** Pipeline que roda
   `npm run build` (React) + `databricks bundle deploy -t prd` no merge para a
   branch principal, para que produção só mude via Git (auditável). *Complexidade
   média; substitui o deploy manual da Fase 10.*
2. **Testes de regressão automatizados.** Suíte de perguntas do Genie com
   respostas esperadas, paridade de medidas (metric view vs Power BI) e
   expectations de qualidade de dados, rodando no CI.
3. **Semântica versionada no bundle.** Passar as metric views/funções/RLS
   (pasta `semantic/`) para dentro do Asset Bundle (hoje aplicadas via SQL manual).
4. **Model Serving com escala a zero + A/B** para os modelos da Fase 6.
5. **Cache semântico de perguntas** (além do cache nativo do Genie/Warehouse),
   se o volume justificar.

## Riscos & decisões a validar
1. **Genie não executa ML nem gera gráfico por si** → o App orquestra forecast/causal/reco e a renderização. Confirmar essa divisão.
2. **Qualidade do Genie depende 100% da Fase 3** → não pular curadoria de metric views/instruções.
3. **Paridade de números vs Power BI** → medidas DAX complexas (RFM, subtotais de DRE com `ISINSCOPE`) exigem tradução cuidadosa; testar exaustivamente.
4. **LakeBase** é relativamente novo → validar disponibilidade na região Azure escolhida; fallback: Azure Database for PostgreSQL.
5. **Custo serverless** (Warehouse + Serving + Apps) → monitorar desde o início (Fase 9).
6. **Caminho mais rápido para um MVP:** Fases 0→2→3(mínimo)→5→7 já entregam os dois chats funcionando; 6/8/9/10 endurecem o produto.
