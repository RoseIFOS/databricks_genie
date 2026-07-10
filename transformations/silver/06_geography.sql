CREATE OR REFRESH MATERIALIZED VIEW geography
(
  CONSTRAINT valid_key EXPECT (geography_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: geography conformado (cidade/estado/país; base geográfica p/ cliente e RLS)'
AS
SELECT
  -- ── CHAVES ──
  CAST(geographykey AS BIGINT) AS geography_key,   -- chave; customer.geography_key aponta p/ cá
  CAST(regionkey    AS BIGINT) AS region_key,      -- FK p/ region (região comercial)

  -- ── ATRIBUTOS DESCRITIVOS (TRIM nas pontas) ──
  TRIM(cityname)               AS city_name,       -- cidade
  TRIM(statecode)              AS state_code,      -- sigla do estado
  TRIM(statename)              AS state_name,      -- nome do estado
  TRIM(countrycode)            AS country_code,    -- código do país
  TRIM(countryname)            AS country_name,    -- nome do país

  -- ── COLUNAS TÉCNICAS ──
  CAST(id AS BIGINT)           AS _source_id,       -- id da origem (lineage + tiebreaker)
  current_timestamp()          AS _silver_loaded_at
FROM hpn.`1_bronze`.geography
-- DEDUP: 1 linha por geografia (id maior = mais recente)
QUALIFY ROW_NUMBER() OVER (PARTITION BY geographykey ORDER BY id DESC) = 1;
