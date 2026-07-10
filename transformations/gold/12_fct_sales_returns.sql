CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.fct_sales_returns
(
  -- ── CHAVES ──
  return_key   BIGINT COMMENT 'Chave de negócio da devolução (BK, grão do fato).',
  customer_key BIGINT COMMENT 'FK -> dim_customer.',
  product_key  BIGINT COMMENT 'FK -> dim_product.',
  return_date  DATE   COMMENT 'FK -> dim_calendar.full_date (data da devolução).',
  order_date   DATE   COMMENT 'FK -> dim_calendar.full_date (data do pedido original; data alternativa).',
  -- ── ATRIBUTOS ──
  sales_order_number STRING COMMENT 'Número do pedido de origem (dimensão degenerada).',
  -- ── MÉTRICAS ──
  return_quantity INT           COMMENT 'Quantidade devolvida.',
  unit_price      DECIMAL(18,4) COMMENT 'Preço unitário do item devolvido.',
  return_amount   DECIMAL(18,4) COMMENT 'Valor devolvido.',
  -- ── AUDITORIA ──
  _gold_loaded_at TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (return_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Fato de devoluções. Grão: 1 devolução.'
AS
SELECT
  return_key,
  customer_key,
  product_key,
  return_date,
  order_date,
  sales_order_number,
  return_quantity,
  unit_price,
  return_amount,
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.sales_returns;
