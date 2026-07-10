CREATE OR REFRESH MATERIALIZED VIEW product_sub_category
(
  CONSTRAINT valid_key EXPECT (product_subcategory_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: product_sub_category conformado (subcategoria + categoria do produto)'
AS
SELECT
  -- ── CHAVES ──
  CAST(productsubcategorykey AS BIGINT) AS product_subcategory_key, -- chave; product.product_subcategory_key aponta p/ cá

    -- ── ATRIBUTOS DESCRITIVOS ──
  TRIM(subcategoryname)                 AS subcategory_name,        -- nome da subcategoria
  TRIM(categoryname)                    AS category_name,           -- nome da categoria (rollup)

  -- ── COLUNAS TÉCNICAS ──
  CAST(id AS BIGINT)                    AS _source_id,              -- id da origem (lineage + tiebreaker)
  current_timestamp()                   AS _silver_loaded_at
FROM hpn.`1_bronze`.product_sub_category
-- DEDUP: 1 linha por subcategoria (id maior = mais recente)
QUALIFY ROW_NUMBER() OVER (PARTITION BY productsubcategorykey ORDER BY id DESC) = 1;
