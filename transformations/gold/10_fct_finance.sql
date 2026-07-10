CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.fct_finance
(
  -- ── CHAVES ──
  finance_key          BIGINT COMMENT 'Chave de negócio do lançamento (BK, degenerada).',
  account_key          BIGINT COMMENT 'FK -> dim_account (conta contábil).',
  organization_key     BIGINT COMMENT 'FK -> dim_organization.',
  department_group_key BIGINT COMMENT 'FK -> dim_department_group.',
  transaction_date     DATE   COMMENT 'FK -> dim_calendar.full_date (data do lançamento).',
  -- ── ATRIBUTOS ──
  scenario STRING COMMENT 'Cenário do lançamento: actual (realizado) ou budget (orçado).',
  -- ── MÉTRICAS ──
  amount DECIMAL(18,4) COMMENT 'Valor do lançamento em USD. O sinal contábil (dim_account.sign) é aplicado na camada semântica, não aqui.',
  -- ── AUDITORIA ──
  _gold_loaded_at TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.',
  CONSTRAINT valid_key EXPECT (finance_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Fato financeiro (DRE). Grão: 1 lançamento (actual vs budget).'
AS
SELECT
  finance_key,
  account_key,
  organization_key,
  department_group_key,
  transaction_date,
  scenario,
  amount,
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.finance;
