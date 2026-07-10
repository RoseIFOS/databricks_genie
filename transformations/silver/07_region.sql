CREATE OR REFRESH MATERIALIZED VIEW region
(
  CONSTRAINT valid_key EXPECT (region_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: region conformado (região/país/continente; usada na RLS regional)'
AS
SELECT

  -- ── CHAVES ──
  CAST(regionkey AS BIGINT) AS region_key,     -- chave; geography.region_key aponta p/ cá

  -- ── ATRIBUTOS DESCRITIVOS ──
  TRIM(region)              AS region_name,     -- nome da região (ex.: será a base do filtro RLS)
  TRIM(country)             AS country,         -- país
  TRIM(continent)           AS continent,       -- continente

  -- ── COLUNAS TÉCNICAS ──
  CAST(id AS BIGINT)        AS _source_id,       -- id da origem (lineage + tiebreaker)
  current_timestamp()       AS _silver_loaded_at

FROM hpn.`1_bronze`.region
-- DEDUP: 1 linha por região (id maior = mais recente)
QUALIFY ROW_NUMBER() OVER (PARTITION BY regionkey ORDER BY id DESC) = 1;
