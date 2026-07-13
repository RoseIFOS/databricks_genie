-- =============================================================================
-- CAMADA SEMÂNTICA — View de consumo FINANCEIRO (base do Metric View financeiro)
-- =============================================================================
-- v_income_statement: lançamentos da DRE (actual vs budget) no grão de LINHA do
-- fato, denormalizados com conta/header/organização/departamento/tempo e com o
-- valor já com sinal contábil aplicado (signed_amount = amount * sign).
-- É a fonte da mv_financeiro. Espelha o padrão de v_sales_transactions (comercial):
-- todos os joins vivem aqui; a metric view NÃO faz joins.
--
-- Naming: catálogo interativo `hpn`; gold = `3_gold`, semântico = `4_semantic`
-- (nomes com dígito inicial exigem backtick). Na promoção dev→prd (Fase 10) o
-- Asset Bundle reconcilia o catálogo (hpn_dev / hpn_prd).
--
-- Comentários de coluna já vivem INLINE no gold (transformations/gold/*.sql);
-- não são reescritos aqui para evitar drift.
-- =============================================================================

CREATE OR REPLACE VIEW hpn.`4_semantic`.v_income_statement
COMMENT 'Lançamentos financeiros da DRE (grão: linha do fato, actual vs budget), denormalizados com conta/header/organização/departamento/tempo. Base da mv_financeiro. signed_amount já aplica o sinal contábil (amount * dim_account.sign), espelhando a composição de DRE do Power BI.'
AS
SELECT
  f.finance_key,
  f.scenario,                                                     -- 'actual' (realizado) | 'budget' (orçado)
  -- ---- Conta / estrutura da DRE ----
  a.account_key,
  a.account_name,
  a.account_type,
  a.account_subheader,
  ah.account_header_key,                                          -- key 3 = Net Sales; base do % VA (trusted query no Genie)
  ah.account_header_name,
  ah.header_detail,                                               -- ordenação do header na DRE
  -- ---- Organização ----
  o.organization_name,
  o.parent_organization,
  -- ---- Departamento ----
  dg.department_group_name,
  -- ---- Tempo (via dim_calendar) ----
  f.transaction_date,
  cal.year        AS year,
  cal.quarter     AS quarter,
  cal.month       AS month,
  cal.month_name  AS month_name,
  -- ---- Métricas ----
  f.amount,                                                       -- valor bruto do lançamento (sem sinal)
  a.sign,                                                         -- sinal contábil (+1/-1) da conta
  CAST(f.amount * a.sign AS DECIMAL(18,4)) AS signed_amount       -- valor com sinal p/ compor a DRE
FROM hpn.`3_gold`.fct_finance f
JOIN hpn.`3_gold`.dim_account          a   ON f.account_key          = a.account_key
JOIN hpn.`3_gold`.dim_account_header   ah  ON a.account_header_key   = ah.account_header_key
JOIN hpn.`3_gold`.dim_organization     o   ON f.organization_key     = o.organization_key
JOIN hpn.`3_gold`.dim_department_group dg  ON f.department_group_key = dg.department_group_key
JOIN hpn.`3_gold`.dim_calendar         cal ON f.transaction_date     = cal.full_date;

-- -----------------------------------------------------------------------------
-- Tags de governança (domínio financeiro) — herdadas pelo Genie/UC.
-- fct_finance e dim_account já foram tagueadas em 01_gold_views.sql; aqui as demais.
-- dim_calendar é compartilhada entre domínios → não taguear como financeiro.
-- -----------------------------------------------------------------------------
ALTER TABLE hpn.`3_gold`.dim_account_header   SET TAGS ('domain' = 'financeiro');
ALTER TABLE hpn.`3_gold`.dim_organization     SET TAGS ('domain' = 'financeiro');
ALTER TABLE hpn.`3_gold`.dim_department_group SET TAGS ('domain' = 'financeiro');

-- -----------------------------------------------------------------------------
-- VALIDAÇÕES (rodar antes de criar a metric view — espelha os checks do comercial)
-- -----------------------------------------------------------------------------
-- V1. Nenhuma linha perdida nos INNER JOINs (órfão de conta/org/depto/data):
--     os dois COUNT têm que bater.
--   SELECT
--     (SELECT COUNT(*) FROM hpn.`3_gold`.fct_finance)              AS gold_linhas,
--     (SELECT COUNT(*) FROM hpn.`4_semantic`.v_income_statement)   AS view_linhas;
--
-- V2. Grão do tempo não infla (dim_calendar deve ter 1 linha por dia):
--   SELECT full_date, COUNT(*) FROM hpn.`3_gold`.dim_calendar
--   GROUP BY full_date HAVING COUNT(*) > 1;   -- espera-se vazio
--
-- V3. Confirmar os cenários existentes (esperado: 'actual' e 'budget'):
--   SELECT scenario, COUNT(*) FROM hpn.`4_semantic`.v_income_statement
--   GROUP BY scenario;
