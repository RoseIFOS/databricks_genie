-- ═══════════════════════════════════════════════════════════════════════
-- MATERIALIZED VIEW: tabela Silver que RECOMPUTA a partir da Bronze.
--   Escolhemos MV (e não STREAMING TABLE) porque a Bronze é overwrite
--   (snapshot completo). MV = "recalcula do zero a cada refresh".
--   CREATE OR REFRESH = cria se não existe, ou atualiza se já existe.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REFRESH MATERIALIZED VIEW customer
(
  -- ── EXPECTATIONS: regras de qualidade (o diferencial da Declarative Pipeline) ──
  -- Sintaxe: CONSTRAINT <nome> EXPECT (<condição>) ON VIOLATION <ação>
  --   ON VIOLATION DROP ROW = linha que viola é DESCARTADA (mas contada no painel de DQ)
  --   (outras ações: FAIL UPDATE = aborta o pipeline; ou sem ação = só conta e mantém)

  -- regra 1: chave de negócio não pode ser nula
  CONSTRAINT valid_key     EXPECT (customer_key IS NOT NULL)  ON VIOLATION DROP ROW,

  -- regra 2: receita anual não pode ser negativa
  CONSTRAINT valid_revenue EXPECT (annual_revenue >= 0)       ON VIOLATION DROP ROW

)
COMMENT "Silver: customer conformado (tipos, trim, dedup por customerkey, auditoria)"
AS
SELECT
  -- ── CASTS: afirmar os tipos corretos (Bronze veio com tipo inferido) ──
  -- CAST(coluna AS TIPO) AS novo_nome  → converte o tipo E renomeia (alias)

  CAST(customerkey     AS BIGINT)          AS customer_key,   -- Chave de negócio, o que os fatos gerenciam
  CAST(geographykey    AS BIGINT)          AS geography_key,  -- FK p/ dimensão geografia

  -- ── TRIM: remove espaços em branco no começo/fim das strings ──
  TRIM(businesstype)                       AS business_type,
  TRIM(customer)                           AS customer_name,
  CAST(numberemployees AS INT)             AS number_employees,   -- nº funcionários (inteiro)
  CAST(annualrevenue   AS DECIMAL(18,2))   AS annual_revenue,     -- dinheiro → DECIMAL(18,2) 18 dig e 2 casas
  CAST(yearopened      AS INT)             AS year_opened,        -- ano (inteiro)

  -- ── coluna TÉCNICA: prefixo "_" sinaliza "não é atributo de negócio" ──
  CAST(id              AS BIGINT)          AS _source_id,     -- id auto da origem (lineage + tiebreaker do dedup)

  -- ── AUDITORIA: quando esta linha passou pela Silver ──
  current_timestamp()                      AS _silver_loaded_at

FROM hpn.`1_bronze`.customer

-- ═══════════════════════════════════════════════════════════════════════
-- QUALIFY: filtra o resultado de uma WINDOW FUNCTION (como um WHERE, mas
--          pra funções de janela). Aqui serve pra DEDUPLICAR.
-- ═══════════════════════════════════════════════════════════════════════
-- ROW_NUMBER() OVER (...)  → numera as linhas dentro de cada grupo:
--   PARTITION BY customerkey → agrupa por cliente (o grupo é "mesmo cliente")
--   ORDER BY id DESC         → dentro do grupo, ordena do id maior p/ menor
--                              (maior id = inserido mais recentemente)
-- = 1                        → fica só a 1ª linha de cada grupo = a mais recente
QUALIFY ROW_NUMBER() OVER (PARTITION BY customerkey ORDER BY id DESC) = 1;
