CREATE OR REFRESH MATERIALIZED VIEW account
(
  -- ── EXPECTATION (regra de qualidade) ──
  -- Referencia o nome FINAL (pós-alias): account_key, não accountkey.
  -- ON VIOLATION DROP ROW = descarta a linha inválida E conta no painel de DQ.
  CONSTRAINT valid_key EXPECT (account_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: account conformado (tipos, trim, dedup por accountkey)'
AS
SELECT
  -- ── CHAVES ──
  CAST(accountkey          AS BIGINT) AS account_key,           -- chave de NEGÓCIO
                                                                --   (usada pelos fatos/joins)

  -- ── ATRIBUTOS DESCRITIVOS (TRIM remove espaços nas pontas) ──
  TRIM(account)                       AS account_name,          -- "account" renomeado p/ clareza
  TRIM(accounttype)                   AS account_type,          -- tipo da conta

  -- ── MÉTRICA/FLAG ──
  CAST(sign                AS INT)    AS sign,                  -- sinal contábil (+1 / -1)

  -- ── FKs (chaves p/ hierarquia de contas) ──
  CAST(accountheaderkey    AS BIGINT) AS account_header_key,    -- FK header
  CAST(accountsubheaderkey AS BIGINT) AS account_subheader_key, -- FK subheader
  TRIM(accountsubheader)              AS account_subheader,     -- descrição do subheader
  CAST(subheaderdetail     AS INT)    AS subheader_detail,      -- detalhe do subheader

  -- ── COLUNAS TÉCNICAS (prefixo "_" = não é atributo de negócio) ──
  CAST(id                  AS BIGINT) AS _source_id,            -- id auto da origem
                                                               --   (lineage + tiebreaker do dedup)
  current_timestamp()                 AS _silver_loaded_at      -- quando passou pela Silver

FROM hpn.`1_bronze`.account

-- ═══════════════════════════════════════════════════════════════════════
-- DEDUP: mantém 1 linha por conta.
--   PARTITION BY accountkey → agrupa por conta (define "duplicata")
--   ORDER BY id DESC        → entre duplicatas, fica a de maior id (mais recente)
--   = 1                     → mantém só a 1ª de cada grupo
-- ═══════════════════════════════════════════════════════════════════════
QUALIFY ROW_NUMBER() OVER (PARTITION BY accountkey ORDER BY id DESC) = 1;
