CREATE OR REFRESH MATERIALIZED VIEW product
(
  CONSTRAINT valid_key EXPECT (product_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: product conformado (produtos; liga-se a product_sub_category p/ categoria)'
AS
SELECT
  -- ── CHAVES ──
  CAST(productkey            AS BIGINT) AS product_key,            -- chave de negócio
  CAST(productsubcategorykey AS BIGINT) AS product_subcategory_key,-- FK p/ product_sub_category

  -- ── ATRIBUTOS DESCRITIVOS ──
  TRIM(productname)                     AS product_name,           -- nome do produto
  TRIM(`Size`)                          AS size,                   -- coluna vinha capitalizada ("Size") → backtick + snake_case
  TRIM(detail)                          AS detail,                 -- detalhe/descrição

  -- ── COLUNAS TÉCNICAS ──
  CAST(id AS BIGINT)                    AS _source_id,             -- id da origem (lineage + tiebreaker)
  current_timestamp()                   AS _silver_loaded_at
FROM hpn.`1_bronze`.product
-- DEDUP: 1 linha por produto (id maior = mais recente)
QUALIFY ROW_NUMBER() OVER (PARTITION BY productkey ORDER BY id DESC) = 1;
