CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.dim_region
(
  -- ── CHAVES ──
  region_key BIGINT COMMENT 'Chave de negócio da região comercial (BK). Referenciada pelo fct_sales_details e pelo dim_geography; âncora da RLS regional.',
  -- ── ATRIBUTOS DESCRITIVOS ──
  region_name STRING COMMENT 'Nome da região comercial.',
  country     STRING COMMENT 'País da região.',
  continent   STRING COMMENT 'Continente da região.',
  -- ── AUDITORIA ──
  _gold_loaded_at TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (region_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Dimensão de regiões comerciais. Grão: 1 linha por região. Base da RLS regional.'
AS
SELECT
  region_key,
  region_name,
  country,
  continent,
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.region;
