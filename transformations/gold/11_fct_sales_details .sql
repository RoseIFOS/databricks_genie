CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.fct_sales_details
(
  -- ── CHAVES ──
  sales_details_key BIGINT COMMENT 'Chave de negócio do item de pedido (BK, grão do fato).',
  sales_header_key  BIGINT COMMENT 'Chave do pedido (dimensão degenerada; agrupa os itens do mesmo pedido).',
  customer_key      BIGINT COMMENT 'FK -> dim_customer (trazido do header).',
  product_key       BIGINT COMMENT 'FK -> dim_product (resolve categoria e subcategoria).',
  region_key        BIGINT COMMENT 'FK -> dim_region (região do pedido, trazida do header).',
  order_date        DATE   COMMENT 'FK -> dim_calendar.full_date (data do pedido).',
  due_date          DATE   COMMENT 'FK -> dim_calendar.full_date (data prevista de entrega).',
  ship_date         DATE   COMMENT 'FK -> dim_calendar.full_date (data de envio).',
  -- ── ATRIBUTOS ──
  sales_order_number STRING COMMENT 'Número do pedido (dimensão degenerada).',
  -- ── MÉTRICAS DE LINHA ──
  order_quantity INT           COMMENT 'Quantidade vendida na linha.',
  unit_price     DECIMAL(18,4) COMMENT 'Preço unitário da linha.',
  gross_sales    DECIMAL(18,4) COMMENT 'Venda BRUTA da linha (= extended_amount da origem: quantidade × preço).',
  -- ── MÉTRICAS DERIVADAS (rateio do desconto do pedido, espelha a ft_sales original) ──
  discount_allocated DECIMAL(18,4) COMMENT 'Desconto do pedido RATEADO à linha: (discount_amount/total_amount do pedido) × venda bruta da linha.',
  net_sales          DECIMAL(18,4) COMMENT 'Venda LÍQUIDA da linha: venda bruta − desconto rateado.',
  -- ── LEAD TIME / OPERACIONAL (não-aditivas: usar MÉDIA, nunca soma) ──
  lead_time_days          INT     COMMENT 'Dias entre pedido e envio (order_date -> ship_date). Não-aditiva: usar média.',
  promised_lead_time_days INT     COMMENT 'Dias prometidos de entrega (order_date -> due_date). Não-aditiva: usar média.',
  delivery_delay_days     INT     COMMENT 'Atraso de envio vs previsto (ship_date − due_date): >0 atrasou, <0 adiantou. Não-aditiva.',
  is_late                 BOOLEAN COMMENT 'Verdadeiro se o envio ocorreu após a data prevista (ship_date > due_date).',
  -- ── AUDITORIA ──
  _gold_loaded_at TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (sales_details_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Fato de vendas no grão de LINHA (espelha a ft_sales original do Apache Hop). Desconto do pedido rateado à linha; inclui métricas de lead time.'
AS
WITH j AS (
  SELECT
    sd.sales_details_key,
    sd.sales_header_key,
    sd.product_key,
    sd.sales_order_number,
    sd.order_quantity,
    sd.unit_price,
    sd.extended_amount,
    sh.customer_key,
    sh.region_key,
    sh.order_date,
    sh.due_date,
    sh.ship_date,
    -- % de desconto do PEDIDO (NULLIF protege total_amount = 0)
    sh.discount_amount / NULLIF(sh.total_amount, 0) AS _discount_pct
  FROM hpn.2_silver.sales_details sd
  LEFT JOIN hpn.2_silver.sales_header sh
    ON sd.sales_header_key = sh.sales_header_key
)
SELECT
  -- ── CHAVES ──
  sales_details_key,
  sales_header_key,
  customer_key,
  product_key,
  region_key,
  order_date,
  due_date,
  ship_date,
  -- ── ATRIBUTOS ──
  sales_order_number,
  -- ── MÉTRICAS DE LINHA ──
  order_quantity,
  unit_price,
  CAST(extended_amount AS DECIMAL(18,4))                                     AS gross_sales,
  -- ── DERIVADAS (rateio) ──
  CAST(_discount_pct * extended_amount AS DECIMAL(18,4))                     AS discount_allocated,
  CAST(extended_amount - (_discount_pct * extended_amount) AS DECIMAL(18,4)) AS net_sales,
  -- ── LEAD TIME / OPERACIONAL ──
  datediff(ship_date, order_date) AS lead_time_days,
  datediff(due_date,  order_date) AS promised_lead_time_days,
  datediff(ship_date, due_date)   AS delivery_delay_days,
  ship_date > due_date            AS is_late,
  -- ── AUDITORIA ──
  current_timestamp() AS _gold_loaded_at
FROM j;

