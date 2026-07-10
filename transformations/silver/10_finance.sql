CREATE OR REFRESH MATERIALIZED VIEW finance
(
  -- Chave do lançamento não pode ser nula.
  CONSTRAINT valid_key      EXPECT (finance_key IS NOT NULL)              ON VIOLATION DROP ROW,
  -- Cenário só pode ser actual/budget (comparado já normalizado p/ minúsculo).
  CONSTRAINT valid_scenario EXPECT (scenario IN ('actual', 'budget'))    ON VIOLATION DROP ROW
)
COMMENT 'Silver: finance conformado (lançamentos DRE actual vs budget). Grão: 1 lançamento.'
AS
SELECT
  -- ── CHAVES ──
  CAST(finance_key          AS BIGINT) AS finance_key,           -- chave de negócio do lançamento (única por linha)
  CAST(account_key          AS BIGINT) AS account_key,           -- FK -> account
  CAST(organization_key     AS BIGINT) AS organization_key,      -- FK -> organization
  CAST(department_group_key AS BIGINT) AS department_group_key,  -- FK -> department_group

  -- ── ATRIBUTOS DESCRITIVOS (TRIM + normalização) ──
  LOWER(TRIM(scenario))                AS scenario,              -- 'Actual'/'Budget' na origem -> minúsculo

  -- ── DATAS (origem em texto dd/MM/yyyy -> to_date) ──
  to_date(transaction_date, 'dd/MM/yyyy') AS transaction_date,   -- data do lançamento

  -- ── MÉTRICAS (origem em texto com VÍRGULA decimal -> replace + decimal 18,4) ──
  CAST(REPLACE(amount, ',', '.') AS DECIMAL(18,4)) AS amount,    -- valor do lançamento (USD)

  -- ── COLUNAS TÉCNICAS (prefixo "_" = não é negócio) ──
  CAST(id AS BIGINT)                   AS _source_id,            -- id da origem (lineage + tiebreaker do dedup)
  current_timestamp()                  AS _silver_loaded_at      -- quando passou pela Silver

FROM hpn.`1_bronze`.finance
-- DEDUP: 1 linha por finance_key (id maior = mais recente)
QUALIFY ROW_NUMBER() OVER (PARTITION BY finance_key ORDER BY id DESC) = 1;
