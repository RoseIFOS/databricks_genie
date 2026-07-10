CREATE OR REFRESH MATERIALIZED VIEW product_cost_history
(
  CONSTRAINT valid_product EXPECT (product_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_cost    EXPECT (unit_cost >= 0)          -- tracked-only
)
COMMENT 'Silver: product_cost_history conformado (custo unitário por produto/mês/país). Grão: produto × mês × país.'
AS
SELECT
  -- ── CHAVES ──
  CAST(productkey AS BIGINT) AS product_key,      -- FK -> product (esta tabela não tem chave surrogate própria)

  -- ── ATRIBUTOS DESCRITIVOS (TRIM) ──
  TRIM(countrycode)          AS country_code,     -- código do país

  -- ── PERÍODO ──
  CAST(`Year`  AS INT)       AS year,             -- ano (origem capitalizada "Year" -> backtick)
  CAST(monthno AS INT)       AS month_no,         -- mês (1-12)

  -- ── MÉTRICAS ──
  CAST(REPLACE(unitcost, ',', '.') AS DECIMAL(18,4)) AS unit_cost,  -- custo unitário

  -- ── COLUNAS TÉCNICAS ──
  CAST(id AS BIGINT)         AS _source_id,
  current_timestamp()        AS _silver_loaded_at
FROM hpn.`1_bronze`.product_cost_history
-- DEDUP: 1 linha por grão composto (produto × mês × país); id maior = mais recente
QUALIFY ROW_NUMBER() OVER (PARTITION BY `Year`, monthno, productkey, countrycode ORDER BY id DESC) = 1;
