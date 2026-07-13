-- =============================================================================
-- CAMADA SEMÂNTICA — View de consumo (base do Metric View comercial)
-- =============================================================================
-- v_sales_transactions: vendas + devoluções unificadas no grão de LINHA,
-- denormalizadas com atributos de cliente/geografia/produto/tempo e enriquecidas
-- com o custo unitário (lookup no histórico). É a fonte da mv_comercial.
--
-- Naming: catálogo interativo `hpn`; schema gold = `3_gold`, semântico = `4_semantic`
-- (nomes com dígito inicial exigem backtick). Na promoção dev→prd (Fase 10), o
-- Asset Bundle reconcilia o catálogo (hpn_dev / hpn_prd).
--
-- Comentários de tabela/coluna já vivem INLINE na camada gold
-- (ver transformations/gold/*.sql) — não são reescritos aqui para evitar drift.
-- =============================================================================

CREATE OR REPLACE VIEW hpn.`4_semantic`.v_sales_transactions
COMMENT 'Transações de venda e devolução unificadas (grão: linha), denormalizadas com atributos de cliente/geografia/produto/tempo. Base da mv_comercial. unit_cost via lookup no histórico de custo (produto × ano/mês do pedido × país do cliente), espelhando a coluna calculada do Power BI.'
AS
WITH sales AS (
  SELECT
    'sale'                                                   AS transaction_type,
    sd.customer_key, sd.product_key, sd.region_key,
    dc.customer_name, dc.business_type,
    dg.region_name, dg.country_name, dg.state_name, dg.city_name, dg.continent,
    dp.category_name, dp.subcategory_name, dp.product_name,
    sd.order_date,
    year(sd.order_date)                                      AS order_year,
    month(sd.order_date)                                     AS order_month,
    sd.order_quantity                                        AS quantity,
    sd.unit_price,
    CAST(sd.order_quantity * sd.unit_price AS DECIMAL(18,4)) AS gross_amount,    -- DAX Gross Sales = qty*price
    sd.discount_allocated                                    AS discount_amount, -- DAX Discounts (rateado à linha)
    pch.unit_cost                                            AS unit_cost        -- DAX [Unit Cost] (lookup)
  FROM hpn.`3_gold`.fct_sales_details sd
  JOIN hpn.`3_gold`.dim_customer  dc ON sd.customer_key = dc.customer_key
  JOIN hpn.`3_gold`.dim_geography dg ON dc.geography_key = dg.geography_key
  JOIN hpn.`3_gold`.dim_product   dp ON sd.product_key  = dp.product_key
  LEFT JOIN hpn.`3_gold`.fct_product_cost_history pch          -- lookup do custo (grão produto×ano/mês×país é único)
    ON  pch.product_key  = sd.product_key
    AND pch.year         = year(sd.order_date)
    AND pch.month_no     = month(sd.order_date)
    AND pch.country_code = dg.country_code
),
returns AS (
  SELECT
    'return'                                                     AS transaction_type,
    sr.customer_key, sr.product_key, dg.region_key,               -- devolução não tem region_key -> via cliente
    dc.customer_name, dc.business_type,
    dg.region_name, dg.country_name, dg.state_name, dg.city_name, dg.continent,
    dp.category_name, dp.subcategory_name, dp.product_name,
    sr.order_date,
    year(sr.order_date)                                          AS order_year,
    month(sr.order_date)                                         AS order_month,
    sr.return_quantity                                           AS quantity,
    sr.unit_price,
    CAST(sr.return_quantity * sr.unit_price AS DECIMAL(18,4))     AS gross_amount, -- DAX Returns = qty*price
    CAST(0    AS DECIMAL(18,4))                                   AS discount_amount,
    CAST(NULL AS DECIMAL(18,4))                                   AS unit_cost
  FROM hpn.`3_gold`.fct_sales_returns sr
  JOIN hpn.`3_gold`.dim_customer  dc ON sr.customer_key = dc.customer_key
  JOIN hpn.`3_gold`.dim_geography dg ON dc.geography_key = dg.geography_key
  JOIN hpn.`3_gold`.dim_product   dp ON sr.product_key  = dp.product_key
)
SELECT * FROM sales
UNION ALL
SELECT * FROM returns;

-- -----------------------------------------------------------------------------
-- Tags de governança (domínio + sensibilidade) — herdadas pelo Genie/UC.
-- -----------------------------------------------------------------------------
ALTER TABLE hpn.`3_gold`.fct_sales_details SET TAGS ('domain' = 'comercial');
ALTER TABLE hpn.`3_gold`.fct_sales_returns SET TAGS ('domain' = 'comercial');
ALTER TABLE hpn.`3_gold`.dim_customer      SET TAGS ('domain' = 'comercial', 'pii' = 'true');
ALTER TABLE hpn.`3_gold`.dim_product       SET TAGS ('domain' = 'comercial');
ALTER TABLE hpn.`3_gold`.fct_finance       SET TAGS ('domain' = 'financeiro');
ALTER TABLE hpn.`3_gold`.dim_account       SET TAGS ('domain' = 'financeiro');
