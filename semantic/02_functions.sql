-- =============================================================================
-- FUNÇÕES SQL & TABELAS DE APOIO — lógica reutilizável (trusted assets do Genie)
-- Substituem a lógica que no Power BI vivia em medidas DAX complexas (RFM, time
-- intelligence) e que NÃO cabe numa metric view. O Genie consome estes objetos
-- como "trusted queries" / example SQL.
--
-- Catálogo interativo `hpn`; schemas `3_gold` e `4_semantic` (dígito inicial →
-- backtick). Na promoção dev→prd (Fase 10) o Asset Bundle troca o catálogo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) RFM — Recency, Frequency, Monetary (tradução das medidas RFM - R/F/M)
--    Materializado como TABELA para performance; refresh via Lakeflow Job (Fase 10).
--    ÂNCORA: a janela de 12 meses é relativa à DATA MÁXIMA do dataset (não a
--    current_date()), porque os dados são históricos — igual ao [... Last 12M] do
--    Power BI, que usa MAX(OrderDate). Com current_date() o resultado sairia vazio.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE hpn.`4_semantic`.dim_customer_rfm AS
WITH anchor AS (
    SELECT MAX(order_date) AS ref_date FROM hpn.`3_gold`.fct_sales_details
),
base AS (
    SELECT
        s.customer_key,
        MAX(s.order_date)                        AS last_purchase,
        datediff(a.ref_date, MAX(s.order_date))  AS recency_days,
        COUNT(DISTINCT s.sales_order_number)     AS sales_orders_12m,
        SUM(s.gross_sales)                       AS gross_sales_12m
    FROM hpn.`3_gold`.fct_sales_details s
    CROSS JOIN anchor a
    WHERE s.order_date >= add_months(a.ref_date, -12)
    GROUP BY s.customer_key, a.ref_date
),
scored AS (
    SELECT
        customer_key,
        last_purchase,
        recency_days,
        sales_orders_12m,
        gross_sales_12m,
        -- RFM - R (recência: quanto mais recente, maior o score)
        CASE
            WHEN recency_days <= 90  THEN 5
            WHEN recency_days <= 180 THEN 4
            WHEN recency_days <= 270 THEN 3
            WHEN recency_days <= 360 THEN 2
            ELSE 1
        END AS r,
        -- RFM - F (frequência: nº de pedidos nos 12 meses)
        CASE
            WHEN sales_orders_12m >= 5 THEN 5
            WHEN sales_orders_12m >= 4 THEN 4
            WHEN sales_orders_12m >= 3 THEN 3
            WHEN sales_orders_12m >= 2 THEN 2
            ELSE 1
        END AS f,
        -- RFM - M (monetário: venda bruta nos 12 meses)
        CASE
            WHEN gross_sales_12m >= 300000 THEN 5
            WHEN gross_sales_12m >= 200000 THEN 4
            WHEN gross_sales_12m >= 100000 THEN 3
            WHEN gross_sales_12m >= 10000  THEN 2
            ELSE 1
        END AS m
    FROM base
)
SELECT
    *,
    (f + m) / 2.0 AS fm,
    -- Segmentação equivalente às classes do Power BI (RFM)
    CASE
        WHEN r >= 5 AND (f + m) / 2.0 > 4                       THEN 'Champions'
        WHEN r  > 2 AND (f + m) / 2.0 > 3                       THEN 'Loyal Customers'
        WHEN r  > 3 AND (f + m) / 2.0 BETWEEN 1 AND 3           THEN 'Potential Loyalist'
        WHEN r >= 5 AND (f + m) / 2.0 <= 1                      THEN 'New Customers'
        WHEN r BETWEEN 3 AND 4 AND (f + m) / 2.0 <= 1           THEN 'Promising'
        WHEN r BETWEEN 3 AND 4 AND (f + m) / 2.0 BETWEEN 2 AND 3 THEN 'Needing Attention'
        WHEN r BETWEEN 2 AND 3 AND (f + m) / 2.0 <= 2           THEN 'About to Sleep'
        WHEN r <= 2 AND (f + m) / 2.0 > 4                       THEN 'At Risk'
        WHEN r <= 1 AND (f + m) / 2.0 > 4                       THEN 'Cant Lose Them'
        WHEN r BETWEEN 1 AND 2 AND (f + m) / 2.0 BETWEEN 1 AND 2 THEN 'Hibernating'
        ELSE 'Lost'
    END AS segment
FROM scored;

COMMENT ON TABLE hpn.`4_semantic`.dim_customer_rfm IS
  'Classificação RFM de clientes (janela de 12 meses ancorada na data máxima de vendas) com segmento (Champions, At Risk, Lost, ...). Refresh via Lakeflow Job.';

-- -----------------------------------------------------------------------------
-- 2) Função de segmento por cliente (uso ad-hoc no Genie/consultas)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hpn.`4_semantic`.customer_segment(p_customer_key BIGINT)
RETURNS STRING
COMMENT 'Retorna o segmento RFM de um cliente.'
RETURN (
    -- MAX() satisfaz a exigência do Databricks de agregar subquery escalar correlacionado.
    -- Há 1 linha por cliente em dim_customer_rfm, então MAX(segment) devolve o próprio segmento.
    SELECT MAX(segment) FROM hpn.`4_semantic`.dim_customer_rfm WHERE customer_key = p_customer_key
);

-- -----------------------------------------------------------------------------
-- 3) Time intelligence — vendas por mês com MoM% e YoY% (trusted asset)
--    Substitui as medidas 'MoM % Gross Sales' / 'YoY% Gross Sales'.
--    Paridade com o DAX: o denominador é o Gross Sales do mês ATUAL
--    (DIVIDE([Gross Sales]-vAnterior, [Gross Sales])) — não o do período anterior.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW hpn.`4_semantic`.v_sales_time_intelligence AS
WITH monthly AS (
    SELECT
        c.year,
        c.year * 100 + c.month AS year_month,       -- YYYYMM (dim_calendar não tem year_month_number)
        SUM(s.gross_sales)     AS gross_sales
    FROM hpn.`3_gold`.fct_sales_details s
    JOIN hpn.`3_gold`.dim_calendar c ON s.order_date = c.full_date
    GROUP BY c.year, c.year * 100 + c.month
)
SELECT
    year,
    year_month,
    gross_sales,
    LAG(gross_sales, 1)  OVER (ORDER BY year_month) AS gross_sales_prev_month,
    LAG(gross_sales, 12) OVER (ORDER BY year_month) AS gross_sales_prev_year,
    (gross_sales - LAG(gross_sales, 1)  OVER (ORDER BY year_month))
        / NULLIF(gross_sales, 0)                     AS mom_pct,
    (gross_sales - LAG(gross_sales, 12) OVER (ORDER BY year_month))
        / NULLIF(gross_sales, 0)                     AS yoy_pct
FROM monthly;

COMMENT ON VIEW hpn.`4_semantic`.v_sales_time_intelligence IS
  'Vendas brutas por mês (YYYYMM) com variação MoM e YoY. Use para perguntas de tendência/crescimento de vendas.';

-- -----------------------------------------------------------------------------
-- NOTA: % VA (Análise Vertical da DRE) também é trusted asset, mas depende de
-- contexto (cada linha ÷ total de Net Sales com ALL(conta)). Melhor registrar como
-- "example SQL" no Genie Space Financeiro (Fase 5) do que como view fixa — o
-- denominador muda conforme o recorte. Base: account_header_key = 3 (Net Sales).
-- =============================================================================
