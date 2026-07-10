CREATE OR REFRESH MATERIALIZED VIEW account_header
(
  -- Chave de negócio não pode ser nula; linha inválida é descartada e contada no DQ.
  CONSTRAINT valid_key EXPECT (account_header_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: account_header conformado (topo da hierarquia de contas p/ DRE)'
AS
SELECT
  -- ── CHAVE DE NEGÓCIO ──
  CAST(accountheaderkey AS BIGINT) AS account_header_key,  -- chave; account.account_header_key aponta p/ cá

  -- ── ATRIBUTO DESCRITIVO (TRIM tira espaços nas pontas) ──
  TRIM(accountheader)              AS account_header_name,  -- nome do header (linha da DRE)

  -- ── DETALHE (inteiro; ordenação/nível do header) ──
  CAST(detail AS INT)              AS header_detail,        -- renomeado p/ deixar claro que é do header

  -- ── COLUNAS TÉCNICAS (prefixo "_" = não é negócio) ──
  CAST(id AS BIGINT)               AS _source_id,           -- id da origem (lineage + tiebreaker do dedup)
  current_timestamp()              AS _silver_loaded_at     -- quando passou pela Silver

FROM hpn.`1_bronze`.account_header

-- DEDUP: 1 linha por header. id maior = mais recente.
QUALIFY ROW_NUMBER() OVER (PARTITION BY accountheaderkey ORDER BY id DESC) = 1;
