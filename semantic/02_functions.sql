-- =============================================================================
-- FUNÇÕES SQL & TABELAS DE APOIO — lógica reutilizável (trusted assets do Genie)
-- Substituem a lógica que no Power BI vivia em medidas DAX complexas.
-- =============================================================================
USE CATALOG hpn_prd;

-- -----------------------------------------------------------------------------
-- 1) RFM — Recency, Frequency, Monetary (tradução das medidas RFM - R/F/M)
--    Materializado como tabela para performance; refresh via Lakeflow Job.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE semantic.dim_customer_rfm AS
WITH base AS (
    SELECT
        s.customer_key,
        MAX(s.order_date)                                   AS last_purchase,
        COUNT(DISTINCT s.sales_order_number)                AS sales_orders_12m,
        SUM(s.order_quantity * s.unit_price)                AS gross_sales_12m
    FROM gold.fct_sales_details s
    WHERE s.order_date >= add_months(current_date(), -12)
    GROUP BY s.customer_key
),
scored AS (
    SELECT
        customer_key,
        last_purchase,
        sales_orders_12m,
        gross_sales_12m,
        -- RFM - R (recência, quanto menor a distância maior o score)
        CASE
            WHEN datediff(current_date(), last_purchase) <= 90  THEN 5
            WHEN datediff(current_date(), last_purchase) <= 180 THEN 4
            WHEN datediff(current_date(), last_purchase) <= 270 THEN 3
            WHEN datediff(current_date(), last_purchase) <= 360 THEN 2
            ELSE 1
        END AS r,
        -- RFM - F (frequência)
        CASE
            WHEN sales_orders_12m >= 5 THEN 5
            WHEN sales_orders_12m >= 4 THEN 4
            WHEN sales_orders_12m >= 3 THEN 3
            WHEN sales_orders_12m >= 2 THEN 2
            ELSE 1
        END AS f,
        -- RFM - M (monetário)
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
    -- Segmentação equivalente às classes do Power BI
    CASE
        WHEN r >= 5 AND (f + m) / 2.0 > 4                     THEN 'Champions'
        WHEN r  > 2 AND (f + m) / 2.0 > 3                     THEN 'Loyal Customers'
        WHEN r  > 3 AND (f + m) / 2.0 BETWEEN 1 AND 3         THEN 'Potential Loyalist'
        WHEN r >= 5 AND (f + m) / 2.0 <= 1                    THEN 'New Customers'
        WHEN r BETWEEN 3 AND 4 AND (f + m) / 2.0 <= 1         THEN 'Promising'
        WHEN r BETWEEN 3 AND 4 AND (f + m) / 2.0 BETWEEN 2 AND 3 THEN 'Needing Attention'
        WHEN r BETWEEN 2 AND 3 AND (f + m) / 2.0 <= 2         THEN 'About to Sleep'
        WHEN r <= 2 AND (f + m) / 2.0 > 4                     THEN 'At Risk'
        WHEN r <= 1 AND (f + m) / 2.0 > 4                     THEN 'Cant Lose Them'
        WHEN r BETWEEN 1 AND 2 AND (f + m) / 2.0 BETWEEN 1 AND 2 THEN 'Hibernating'
        ELSE 'Lost'
    END AS segment
FROM scored;

COMMENT ON TABLE semantic.dim_customer_rfm IS
  'Classificação RFM de clientes (últimos 12 meses) com segmento (Champions, At Risk, Lost, ...). Refresh diário.';

-- -----------------------------------------------------------------------------
-- 2) Função de segmento por cliente (para uso ad-hoc no Genie/consultas)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION semantic.customer_segment(p_customer_key BIGINT)
RETURNS STRING
COMMENT 'Retorna o segmento RFM de um cliente.'
RETURN (
    SELECT segment FROM semantic.dim_customer_rfm WHERE customer_key = p_customer_key
);

-- -----------------------------------------------------------------------------
-- 3) Time intelligence — vendas com YoY e MoM por mês (trusted asset)
--    Substitui as medidas YoY% / MoM% Gross Sales.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW semantic.v_sales_time_intelligence AS
WITH monthly AS (
    SELECT
        c.year,
        c.year_month_number,
        SUM(s.order_quantity * s.unit_price) AS gross_sales
    FROM gold.fct_sales_details s
    JOIN gold.dim_calendar c ON s.order_date = c.date_id
    GROUP BY c.year, c.year_month_number
)
SELECT
    year,
    year_month_number,
    gross_sales,
    LAG(gross_sales, 1)  OVER (ORDER BY year_month_number) AS gross_sales_prev_month,
    LAG(gross_sales, 12) OVER (ORDER BY year_month_number) AS gross_sales_prev_year,
    (gross_sales - LAG(gross_sales, 1)  OVER (ORDER BY year_month_number))
        / NULLIF(gross_sales, 0)                            AS mom_pct,
    (gross_sales - LAG(gross_sales, 12) OVER (ORDER BY year_month_number))
        / NULLIF(gross_sales, 0)                            AS yoy_pct
FROM monthly;

COMMENT ON VIEW semantic.v_sales_time_intelligence IS
  'Vendas brutas por mês com variação MoM e YoY. Use para perguntas de tendência/crescimento.';
