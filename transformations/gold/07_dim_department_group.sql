CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.dim_department_group
(
  -- ── CHAVES ──
  department_group_key BIGINT COMMENT 'Chave de negócio do grupo de departamentos (BK). Referenciada pelo fato finance.',
  -- ── ATRIBUTOS DESCRITIVOS ──
  department_group_name STRING COMMENT 'Nome do grupo de departamentos.',
  -- ── AUDITORIA ──
  _gold_loaded_at TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (department_group_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Dimensão de grupos de departamentos. Grão: 1 linha por grupo.'
AS
SELECT
  department_group_key,
  department_group_name,
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.department_group;
