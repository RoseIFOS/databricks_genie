CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.dim_account
(
  -- ── CHAVES ──
  account_key           BIGINT COMMENT 'Chave de negócio da conta contábil (BK). Referenciada pelo fato finance.',
  account_header_key    BIGINT COMMENT 'Chave do header da conta (topo da DRE).',
  account_subheader_key BIGINT COMMENT 'Chave do subheader da conta (nível intermediário da DRE).',
  -- ── ATRIBUTOS DESCRITIVOS ──
  account_name      STRING COMMENT 'Nome da conta contábil.',
  account_type      STRING COMMENT 'Tipo da conta.',
  account_subheader STRING COMMENT 'Descrição do subheader da conta.',
  subheader_detail  INT    COMMENT 'Ordenação/detalhe do subheader.',
  -- ── MÉTRICA/FLAG ──
  sign              INT    COMMENT 'Sinal contábil (+1/-1) aplicado ao valor na composição da DRE.',
  -- ── AUDITORIA ──
  _gold_loaded_at   TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (account_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Dimensão de contas contábeis (conta → subheader → header da DRE). Grão: 1 linha por conta.'
AS
SELECT
  -- ── CHAVES ──
  account_key,
  account_header_key,
  account_subheader_key,
  -- ── ATRIBUTOS DESCRITIVOS ──
  account_name,
  account_type,
  account_subheader,
  subheader_detail,
  -- ── MÉTRICA/FLAG ──
  sign,
  -- ── AUDITORIA ──
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.account;
