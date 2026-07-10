CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.dim_geography
(
  -- ── CHAVES ──
  geography_key BIGINT COMMENT 'Chave de negócio da localização (BK). Referenciada pelo dim_customer.',
  region_key    BIGINT COMMENT 'Chave da região comercial (agregação usada na RLS regional).',
  -- ── ATRIBUTOS GEOGRÁFICOS (do mais amplo ao mais específico) ──
  continent     STRING COMMENT 'Continente (topo da hierarquia geográfica).',
  region_name   STRING COMMENT 'Nome da região comercial.',
  country_code  STRING COMMENT 'Código do país (ISO).',
  country_name  STRING COMMENT 'Nome do país.',
  state_code    STRING COMMENT 'Sigla do estado/província.',
  state_name    STRING COMMENT 'Nome do estado/província.',
  city_name     STRING COMMENT 'Cidade.',
  -- ── AUDITORIA ──
  _gold_loaded_at TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (geography_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Dimensão geográfica (cidade → estado → país → região → continente). Grão: 1 linha por localização.'
AS
SELECT
  -- ── CHAVES ──
  g.geography_key,
  g.region_key,
  -- ── ATRIBUTOS GEOGRÁFICOS ──
  r.continent,
  r.region_name,
  g.country_code,
  g.country_name,
  g.state_code,
  g.state_name,
  g.city_name,
  -- ── AUDITORIA ──
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.geography g
LEFT JOIN hpn.2_silver.region r ON g.region_key = r.region_key;
