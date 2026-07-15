-- =============================================================================
-- GENIE SPACE FINANCEIRO — Instruções granulares (Example queries)
-- -----------------------------------------------------------------------------
-- Cadastro na UI: Genie Space > Instructions > seção Examples > "Add > Example query".
-- Campos por bloco:
--   -- P:     pergunta (título)
--   -- GUIA:  Usage Guidance (quando usar)
--   -- PARAM: parâmetros (:nome) — só quando aplicável
--   SQL:     corpo
--
-- Sintaxe de metric view: SELECT `Dim`, MEASURE(`Measure`) FROM mv GROUP BY `Dim`.
-- Catálogo `hpn`, schema `4_semantic`.
-- OBS: não há JOINS a cadastrar aqui — mv_financeiro e v_income_statement já são
--      denormalizadas (todos os joins vivem em 02_gold_views_financeiro.sql).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- P: Qual foi o total realizado e o orçado?
-- GUIA: Padrão base — realizado vs orçado global, sem recorte.
-- -----------------------------------------------------------------------------
SELECT MEASURE(`Total Amount Actual`) AS realizado,
       MEASURE(`Total Amount Budget`) AS orcado
FROM hpn.`4_semantic`.mv_financeiro;

-- -----------------------------------------------------------------------------
-- P: Realizado vs orçado por linha da DRE
-- GUIA: Comparação por linha de topo da DRE. Mostra os dois valores + desvio.
-- -----------------------------------------------------------------------------
SELECT `LinhaDRE`,
       MEASURE(`Total Amount Actual`) AS realizado,
       MEASURE(`Total Amount Budget`) AS orcado,
       MEASURE(`Budget Deviation`)    AS desvio,
       MEASURE(`Budget Deviation %`)  AS desvio_pct
FROM hpn.`4_semantic`.mv_financeiro
GROUP BY `LinhaDRE`
ORDER BY desvio;

-- -----------------------------------------------------------------------------
-- P: Quais contas tiveram maior desvio orçamentário?
-- GUIA: Ranking de desvio por conta. Desvio positivo = acima do orçado.
-- -----------------------------------------------------------------------------
SELECT `Conta`,
       MEASURE(`Total Amount Actual`) AS realizado,
       MEASURE(`Total Amount Budget`) AS orcado,
       MEASURE(`Budget Deviation`)    AS desvio
FROM hpn.`4_semantic`.mv_financeiro
GROUP BY `Conta`
ORDER BY ABS(MEASURE(`Budget Deviation`)) DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- P: Como evoluiu o realizado ao longo dos meses?
-- GUIA: Série temporal do realizado. Para variação % use desvio vs orçado, não MoM.
-- -----------------------------------------------------------------------------
SELECT `Ano`, `Mes`,
       MEASURE(`Total Amount Actual`) AS realizado
FROM hpn.`4_semantic`.mv_financeiro
GROUP BY `Ano`, `Mes`
ORDER BY `Ano`, `Mes`;

-- -----------------------------------------------------------------------------
-- P: Realizado vs orçado em 2025 (ou em um ano específico)
-- GUIA: Filtra por UM ano. O Genie injeta o ano em :ano.
-- PARAM: ano (INT) — ex.: 2025
-- -----------------------------------------------------------------------------
SELECT `Ano`,
       MEASURE(`Total Amount Actual`) AS realizado,
       MEASURE(`Total Amount Budget`) AS orcado,
       MEASURE(`Budget Deviation`)    AS desvio
FROM hpn.`4_semantic`.mv_financeiro
WHERE `Ano` = :ano
GROUP BY `Ano`;

-- -----------------------------------------------------------------------------
-- P: Realizado por organização
-- GUIA: Measure por dimensão organizacional. Serve de molde para "X por organização".
-- -----------------------------------------------------------------------------
SELECT `Organizacao`,
       MEASURE(`Total Amount Actual`) AS realizado
FROM hpn.`4_semantic`.mv_financeiro
GROUP BY `Organizacao`
ORDER BY realizado DESC;

-- -----------------------------------------------------------------------------
-- P: Qual a análise vertical (% VA) da DRE? / Cada linha representa quanto da receita líquida?
-- GUIA: ANÁLISE VERTICAL — NÃO cabe na metric view. Cada linha da DRE ÷ Net Sales.
--       Denominador FIXO = account_header_key = 3 (Net Sales), cenário 'actual'.
--       Use SEMPRE que a pergunta for "% da receita", "análise vertical", "% VA",
--       "peso de cada linha/conta na receita".
-- -----------------------------------------------------------------------------
WITH net_sales AS (
    SELECT SUM(signed_amount) AS base
    FROM hpn.`4_semantic`.v_income_statement
    WHERE scenario = 'actual'
      AND account_header_key = 3          -- 3 = Net Sales (Receita Líquida)
)
SELECT i.account_header_name                     AS linha_dre,
       SUM(i.signed_amount)                      AS valor,
       SUM(i.signed_amount) / NULLIF(ns.base, 0) AS va_pct
FROM hpn.`4_semantic`.v_income_statement i
CROSS JOIN net_sales ns
WHERE i.scenario = 'actual'
GROUP BY i.account_header_name, ns.base
ORDER BY va_pct DESC;

-- -----------------------------------------------------------------------------
-- P: Qual a análise vertical (% VA) por conta?
-- GUIA: Mesma regra do % VA, mas no grão de CONTA (não de linha da DRE).
--       Denominador continua Net Sales (account_header_key = 3), cenário 'actual'.
-- -----------------------------------------------------------------------------
WITH net_sales AS (
    SELECT SUM(signed_amount) AS base
    FROM hpn.`4_semantic`.v_income_statement
    WHERE scenario = 'actual'
      AND account_header_key = 3
)
SELECT i.account_header_name                     AS linha_dre,
       i.account_name                            AS conta,
       SUM(i.signed_amount)                      AS valor,
       SUM(i.signed_amount) / NULLIF(ns.base, 0) AS va_pct
FROM hpn.`4_semantic`.v_income_statement i
CROSS JOIN net_sales ns
WHERE i.scenario = 'actual'
GROUP BY i.account_header_name, i.account_name, ns.base
ORDER BY va_pct DESC;
