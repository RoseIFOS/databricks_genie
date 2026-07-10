CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.dim_calendar
(
  -- ── CHAVES ──
  date_key   INT  COMMENT 'Chave inteira da data (YYYYMMDD). Útil p/ ordenação e Power BI.',
  full_date  DATE COMMENT 'Data. Chave de join com as colunas de data dos fatos.',
  -- ── ATRIBUTOS DE CALENDÁRIO ──
  year         INT     COMMENT 'Ano.',
  quarter      INT     COMMENT 'Trimestre (1-4).',
  month        INT     COMMENT 'Mês (1-12).',
  month_name   STRING  COMMENT 'Nome do mês em português.',
  day          INT     COMMENT 'Dia do mês.',
  day_of_week  INT     COMMENT 'Dia da semana (1=domingo … 7=sábado).',
  week_of_year INT     COMMENT 'Semana do ano.',
  is_weekend   BOOLEAN COMMENT 'Verdadeiro se sábado ou domingo.',
  -- ── AUDITORIA ──
  _gold_loaded_at TIMESTAMP COMMENT 'Técnico: quando a linha foi materializada no Gold.'
)
COMMENT 'Dimensão de calendário GERADA (não existe na origem). Grão: 1 linha por dia; cobre o período dos fatos.'
AS
WITH bounds AS (
  -- trunc(...,'YEAR') retorna DATE (date_trunc retornaria TIMESTAMP e quebraria o full_date)
  SELECT
    trunc(MIN(d), 'YEAR')                           AS start_date,   -- 1º dia do ano mínimo
    last_day(add_months(trunc(MAX(d), 'YEAR'), 11)) AS end_date      -- 31/dez do ano máximo
  FROM (
    SELECT transaction_date AS d FROM hpn.`2_silver`.finance
    UNION ALL SELECT order_date  FROM hpn.`2_silver`.sales_header
    UNION ALL SELECT due_date    FROM hpn.`2_silver`.sales_header
    UNION ALL SELECT ship_date   FROM hpn.`2_silver`.sales_header
    UNION ALL SELECT return_date FROM hpn.`2_silver`.sales_returns
    UNION ALL SELECT order_date  FROM hpn.`2_silver`.sales_returns
  ) WHERE d IS NOT NULL
),

days AS (
  -- Uma linha por dia entre start_date e end_date.
  SELECT explode(sequence(start_date, end_date, INTERVAL 1 DAY)) AS full_date FROM bounds
)
SELECT
  -- ── CHAVES ──
  CAST(date_format(full_date, 'yyyyMMdd') AS INT) AS date_key,
  full_date,
  -- ── ATRIBUTOS DE CALENDÁRIO ──
  year(full_date)    AS year,
  quarter(full_date) AS quarter,
  month(full_date)   AS month,
  CASE month(full_date)
    WHEN 1 THEN 'Janeiro'  WHEN 2 THEN 'Fevereiro' WHEN 3 THEN 'Março'
    WHEN 4 THEN 'Abril'    WHEN 5 THEN 'Maio'       WHEN 6 THEN 'Junho'
    WHEN 7 THEN 'Julho'    WHEN 8 THEN 'Agosto'     WHEN 9 THEN 'Setembro'
    WHEN 10 THEN 'Outubro' WHEN 11 THEN 'Novembro'  WHEN 12 THEN 'Dezembro'
  END                AS month_name,
  day(full_date)        AS day,
  dayofweek(full_date)  AS day_of_week,
  weekofyear(full_date) AS week_of_year,
  dayofweek(full_date) IN (1, 7) AS is_weekend,
  -- ── AUDITORIA ──
  current_timestamp()   AS _gold_loaded_at
FROM days;
