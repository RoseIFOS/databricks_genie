CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.dim_product
(
  -- ── CHAVES ──
  product_key             BIGINT COMMENT 'Chave de negócio do produto (BK). Referenciada pelos fatos de vendas/devoluções/custo.',
  product_subcategory_key BIGINT COMMENT 'Chave da subcategoria (nível intermediário da hierarquia).',
  -- ── ATRIBUTOS (do mais amplo ao mais específico) ──
  category_name    STRING COMMENT 'Categoria do produto (topo da hierarquia).',
  subcategory_name STRING COMMENT 'Subcategoria do produto.',
  product_name     STRING COMMENT 'Nome do produto.',
  size             STRING COMMENT 'Tamanho do produto.',
  detail           STRING COMMENT 'Detalhe/descrição adicional do produto.',
  -- ── AUDITORIA ──
  _gold_loaded_at  TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (product_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Dimensão de produtos (produto → subcategoria → categoria). Grão: 1 linha por produto.'
AS
SELECT
  -- ── CHAVES ──
  p.product_key,
  p.product_subcategory_key,
  -- ── ATRIBUTOS ──
  psc.category_name,
  psc.subcategory_name,
  p.product_name,
  p.size,
  p.detail,
  -- ── AUDITORIA ──
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.product p
LEFT JOIN hpn.2_silver.product_sub_category psc
  ON p.product_subcategory_key = psc.product_subcategory_key;
