CREATE OR REFRESH MATERIALIZED VIEW sales_header
(
  CONSTRAINT valid_key   EXPECT (sales_header_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_total EXPECT (total_amount >= 0)   -- tracked-only (sem DROP): sinaliza, não perde pedido
)
COMMENT 'Silver: sales_header conformado (cabeçalho do pedido). Grão: 1 pedido.'
AS
SELECT
  -- ── CHAVES ──
  CAST(salesheaderkey AS BIGINT) AS sales_header_key,   -- chave de negócio do pedido (única por linha)
  CAST(customerkey    AS BIGINT) AS customer_key,       -- FK -> customer
  CAST(regionkey      AS BIGINT) AS region_key,         -- FK -> region

  -- ── ATRIBUTOS DESCRITIVOS (TRIM) ──
  TRIM(salesordernumber)         AS sales_order_number, -- número do pedido

  -- ── DATAS (texto dd/MM/yyyy -> to_date) ──
  to_date(orderdate, 'dd/MM/yyyy') AS order_date,       -- data do pedido
  to_date(duedate,   'dd/MM/yyyy') AS due_date,         -- data prevista de entrega
  to_date(shipdate,  'dd/MM/yyyy') AS ship_date,        -- data de envio

  -- ── MÉTRICAS (texto com vírgula -> replace + decimal 18,4) ──
  CAST(REPLACE(discountamount, ',', '.') AS DECIMAL(18,4)) AS discount_amount, -- desconto
  CAST(REPLACE(totalamount,    ',', '.') AS DECIMAL(18,4)) AS total_amount,    -- total bruto do pedido
  CAST(REPLACE(salesamount,    ',', '.') AS DECIMAL(18,4)) AS sales_amount,    -- venda líquida

  -- ── COLUNAS TÉCNICAS ──
  CAST(id AS BIGINT)             AS _source_id,
  current_timestamp()            AS _silver_loaded_at
FROM hpn.`1_bronze`.sales_header
-- DEDUP: 1 linha por pedido (id maior = mais recente)
QUALIFY ROW_NUMBER() OVER (PARTITION BY salesheaderkey ORDER BY id DESC) = 1;
