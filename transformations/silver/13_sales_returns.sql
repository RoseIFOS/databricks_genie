CREATE OR REFRESH MATERIALIZED VIEW sales_returns
(
  CONSTRAINT valid_key      EXPECT (return_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_quantity EXPECT (return_quantity >= 0)   -- tracked-only
)
COMMENT 'Silver: sales_returns conformado (devoluções). Grão: 1 devolução.'
AS
SELECT
  -- ── CHAVES ──
  CAST(returnkey   AS BIGINT) AS return_key,         -- chave de negócio da devolução (única por linha)
  CAST(customerkey AS BIGINT) AS customer_key,       -- FK -> customer
  CAST(productkey  AS BIGINT) AS product_key,        -- FK -> product

  -- ── ATRIBUTOS DESCRITIVOS (TRIM) ──
  TRIM(salesordernumber)      AS sales_order_number, -- número do pedido de origem

  -- ── DATAS (texto dd/MM/yyyy -> to_date) ──
  to_date(returndate, 'dd/MM/yyyy') AS return_date,  -- data da devolução
  to_date(orderdate,  'dd/MM/yyyy') AS order_date,   -- data do pedido original

  -- ── MÉTRICAS ──
  CAST(returnquantity AS INT)  AS return_quantity,   -- quantidade devolvida (origem já inteira)
  CAST(REPLACE(unitprice,    ',', '.') AS DECIMAL(18,4)) AS unit_price,    -- preço unitário
  CAST(REPLACE(returnamount, ',', '.') AS DECIMAL(18,4)) AS return_amount, -- valor devolvido

  -- ── COLUNAS TÉCNICAS ──
  CAST(id AS BIGINT)          AS _source_id,
  current_timestamp()         AS _silver_loaded_at
FROM hpn.`1_bronze`.sales_returns
-- DEDUP: 1 linha por devolução (id maior = mais recente)
QUALIFY ROW_NUMBER() OVER (PARTITION BY returnkey ORDER BY id DESC) = 1;
