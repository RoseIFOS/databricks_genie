CREATE OR REFRESH MATERIALIZED VIEW organization
(
  -- Chave de negócio não pode ser nula; linha inválida é descartada e contada no DQ.
  CONSTRAINT valid_key EXPECT (organization_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: organization conformado (unidades organizacionais p/ o domínio financeiro)'
AS
SELECT
  -- ── CHAVE DE NEGÓCIO ──
  CAST(organizationkey AS BIGINT) AS organization_key,    -- chave; finance.organization_key aponta p/ cá

  -- ── ATRIBUTOS DESCRITIVOS (TRIM tira espaços nas pontas) ──
  TRIM(organization)              AS organization_name,    -- nome da unidade organizacional
  TRIM(parentorganization)        AS parent_organization,  -- unidade-pai (hierarquia organizacional)

  -- ── COLUNAS TÉCNICAS (prefixo "_" = não é negócio) ──
  CAST(id AS BIGINT)              AS _source_id,            -- id da origem (lineage + tiebreaker do dedup)
  current_timestamp()             AS _silver_loaded_at      -- quando passou pela Silver

FROM hpn.`1_bronze`.organization

-- DEDUP: 1 linha por organização. id maior = mais recente.
QUALIFY ROW_NUMBER() OVER (PARTITION BY organizationkey ORDER BY id DESC) = 1;
