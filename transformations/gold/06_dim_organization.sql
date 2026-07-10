CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.dim_organization
(
  -- ── CHAVES ──
  organization_key BIGINT COMMENT 'Chave de negócio da organização (BK). Referenciada pelo fato finance.',
  -- ── ATRIBUTOS DESCRITIVOS ──
  organization_name   STRING COMMENT 'Nome da unidade organizacional.',
  parent_organization STRING COMMENT 'Organização-pai (hierarquia organizacional).',
  -- ── AUDITORIA ──
  _gold_loaded_at  TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (organization_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Dimensão de organizações (unidades organizacionais). Grão: 1 linha por organização.'
AS
SELECT
  organization_key,
  organization_name,
  parent_organization,
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.organization;
