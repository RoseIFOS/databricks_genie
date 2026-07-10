CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.dim_account_header
(
  -- ── CHAVES ──
  account_header_key BIGINT COMMENT 'Chave de negócio do header de conta (BK). Topo da hierarquia da DRE.',
  -- ── ATRIBUTOS DESCRITIVOS ──
  account_header_name STRING COMMENT 'Nome do header (linha de topo da DRE).',
  header_detail       INT    COMMENT 'Ordenação/nível do header.',
  -- ── AUDITORIA ──
  _gold_loaded_at     TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (account_header_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Dimensão de headers de conta (agrupador de topo da DRE). Grão: 1 linha por header.'
AS
SELECT
  account_header_key,
  account_header_name,
  header_detail,
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.account_header;
