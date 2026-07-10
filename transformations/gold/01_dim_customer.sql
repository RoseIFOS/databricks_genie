CREATE OR REFRESH MATERIALIZED VIEW hpn.3_gold.dim_customer
(
  -- ── SCHEMA + COMENTÁRIOS DE NEGÓCIO (o que o Genie lê como contexto semântico) ──
  -- ── CHAVES ──
  customer_key     BIGINT        COMMENT 'Chave de negócio do cliente (BK). Liga os fatos de vendas e devoluções a este cliente.',
  geography_key    BIGINT        COMMENT 'Chave para dim_geography: localização (cidade/estado/país/região) do cliente.',

  -- ── ATRIBUTOS DESCRITIVOS ──
  customer_name    STRING        COMMENT 'Nome do cliente.',
  business_type    STRING        COMMENT 'Tipo/segmento de negócio do cliente.',
  number_employees INT           COMMENT 'Número de funcionários do cliente.',
  annual_revenue   DECIMAL(18,2) COMMENT 'Receita anual declarada do cliente, em dólares (USD).',
  year_opened      INT           COMMENT 'Ano de fundação/abertura do cliente.',

  -- ── AUDITORIA ──
  _gold_loaded_at  TIMESTAMP     COMMENT 'Técnico: quando a linha foi materializada no Gold.',

  -- ── QUALIDADE ──
  CONSTRAINT valid_key EXPECT (customer_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Dimensão de clientes. Grão: 1 linha por cliente. Atributos de quem compra (usada nas análises comerciais).'
AS
SELECT
  -- ── CHAVES ──
  customer_key,
  geography_key,

  -- ── ATRIBUTOS DESCRITIVOS ──
  customer_name,
  business_type,
  number_employees,
  annual_revenue,
  year_opened,

  -- ── AUDITORIA ──
  current_timestamp() AS _gold_loaded_at
FROM hpn.2_silver.customer;
-- Sem dedup: a Silver já entregou 1 linha por cliente.
