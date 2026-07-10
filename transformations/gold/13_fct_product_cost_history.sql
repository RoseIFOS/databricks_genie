CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.fct_product_cost_history
(
  -- ── CHAVES ──
  product_key BIGINT COMMENT 'FK -> dim_product.',
  year        INT    COMMENT 'Ano de referência do custo (junta com dim_calendar.year).',
  month_no    INT    COMMENT 'Mês de referência 1-12 (junta com dim_calendar.month).',
  -- ── ATRIBUTOS ──
  country_code STRING COMMENT 'Código do país do custo (dimensão degenerada).',
  -- ── MÉTRICAS ──
  unit_cost DECIMAL(18,4) COMMENT 'Custo unitário do produto no período/país.',
  -- ── AUDITORIA ──
  _gold_loaded_at TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_product EXPECT (product_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Fato de histórico de custo unitário. Grão: produto × mês × país.'
AS
SELECT
  product_key,
  year,
  month_no,
  country_code,
  unit_cost,
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.product_cost_history;
