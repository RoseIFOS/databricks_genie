CREATE OR REFRESH MATERIALIZED VIEW sales_details
(
  CONSTRAINT valid_key      EXPECT (sales_details_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_quantity EXPECT (order_quantity >= 0),  -- tracked-only
  CONSTRAINT valid_price    EXPECT (unit_price >= 0)        -- tracked-only
)
COMMENT 'Silver: sales_details conformado (item do pedido). Grão: 1 linha de item.'
AS
SELECT
  -- ── CHAVES ──
  CAST(salesdetailskey       AS BIGINT) AS sales_details_key,        -- chave de negócio do item (única por linha)
  CAST(salesheaderkey        AS BIGINT) AS sales_header_key,         -- FK -> sales_header (repete; NÃO é chave de dedup)
  CAST(productkey            AS BIGINT) AS product_key,              -- FK -> product
  CAST(productsubcategorykey AS BIGINT) AS product_subcategory_key,  -- FK -> product_sub_category

  -- ── ATRIBUTOS DESCRITIVOS (TRIM) ──
  TRIM(salesordernumber)                AS sales_order_number,       -- número do pedido

  -- ── MÉTRICAS ──
  CAST(orderquantity AS INT)            AS order_quantity,           -- quantidade (origem já inteira)
  CAST(REPLACE(unitprice,      ',', '.') AS DECIMAL(18,4)) AS unit_price,      -- preço unitário
  CAST(REPLACE(extendedamount, ',', '.') AS DECIMAL(18,4)) AS extended_amount, -- valor estendido (qtd × preço)

  -- ── COLUNAS TÉCNICAS ──
  CAST(id AS BIGINT)                    AS _source_id,
  current_timestamp()                   AS _silver_loaded_at
FROM hpn.`1_bronze`.sales_details
-- DEDUP: 1 linha por item (id maior = mais recente)
QUALIFY ROW_NUMBER() OVER (PARTITION BY salesdetailskey ORDER BY id DESC) = 1;
