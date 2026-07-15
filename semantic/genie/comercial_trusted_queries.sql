-- =============================================================================
-- GENIE SPACE COMERCIAL — Instruções granulares (Joins + Example queries)
-- -----------------------------------------------------------------------------
-- Cadastro na UI: Genie Space > Instructions > seção Examples > botão "Add".
-- Cada bloco abaixo indica o TIPO de instrução e os campos:
--   -- P:     pergunta (título do Example query)
--   -- GUIA:  Usage Guidance (quando o Genie deve usar este exemplo)
--   -- PARAM: parâmetros a declarar (troca literal por :nome) — só quando aplicável
--   SQL:     corpo do Example query
--
-- Ordem recomendada de cadastro: (1) JOINS, (2) EXAMPLE QUERIES.
-- Sintaxe de metric view: SELECT `Dim`, MEASURE(`Measure`) FROM mv GROUP BY `Dim`.
-- Catálogo `hpn`, schema `4_semantic`. Na promoção dev->prd o Asset Bundle troca o catálogo.
-- =============================================================================


-- #############################################################################
-- SEÇÃO 1 — JOINS  (Add > Join)
-- Ensinam o Genie a juntar tabelas com segurança. Sem isto ele chuta a chave.
-- #############################################################################

-- JOIN 1: RFM -> transações (para obter nome/atributos do cliente a partir do segmento)
--   Tabela esquerda : hpn.4_semantic.dim_customer_rfm   (coluna: customer_key)
--   Tabela direita  : hpn.4_semantic.v_sales_transactions (coluna: customer_key)
--   Tipo            : INNER
--   Chave           : dim_customer_rfm.customer_key = v_sales_transactions.customer_key
--   Uso             : perguntas que pedem NOME do cliente + segmento RFM.


-- #############################################################################
-- SEÇÃO 2 — EXAMPLE QUERIES  (Add > Example query)
-- #############################################################################

-- -----------------------------------------------------------------------------
-- P: Qual foi o total de vendas líquidas?
-- GUIA: Padrão base — consultar uma measure sem recorte. Use para totais globais.
-- -----------------------------------------------------------------------------
SELECT MEASURE(`Net Sales`) AS net_sales
FROM hpn.`4_semantic`.mv_comercial;

-- -----------------------------------------------------------------------------
-- P: Vendas líquidas por região
-- GUIA: Measure agregada por uma dimensão, ordenada. Serve de molde para "X por <dimensão>".
-- -----------------------------------------------------------------------------
SELECT `Regiao`,
       MEASURE(`Net Sales`) AS net_sales
FROM hpn.`4_semantic`.mv_comercial
GROUP BY `Regiao`
ORDER BY net_sales DESC;

-- -----------------------------------------------------------------------------
-- P: Vendas líquidas na região Sul (ou em uma região específica)
-- GUIA: Use quando o usuário filtra por UMA região. O Genie injeta o nome em :regiao.
-- PARAM: regiao (STRING) — ex.: 'South', 'North'
-- -----------------------------------------------------------------------------
SELECT `Regiao`,
       MEASURE(`Net Sales`) AS net_sales
FROM hpn.`4_semantic`.mv_comercial
WHERE `Regiao` = :regiao
GROUP BY `Regiao`;

-- -----------------------------------------------------------------------------
-- P: Quais os 10 produtos com maior venda líquida?
-- GUIA: Top N por measure. Ajuste o LIMIT conforme "top 5 / top 20".
-- -----------------------------------------------------------------------------
SELECT `Produto`,
       MEASURE(`Net Sales`) AS net_sales
FROM hpn.`4_semantic`.mv_comercial
GROUP BY `Produto`
ORDER BY net_sales DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- P: Qual a margem bruta % por categoria de produto?
-- GUIA: Measure percentual por dimensão. Para margem em valor use `Gross Margin`.
-- -----------------------------------------------------------------------------
SELECT `Categoria`,
       MEASURE(`Gross Margin %`) AS gross_margin_pct,
       MEASURE(`Net Sales`)      AS net_sales
FROM hpn.`4_semantic`.mv_comercial
GROUP BY `Categoria`
ORDER BY gross_margin_pct DESC;

-- -----------------------------------------------------------------------------
-- P: Qual a taxa de devolução por região?
-- GUIA: Use para perguntas de devolução/return rate. `% Returns` = Returns / Gross Sales.
-- -----------------------------------------------------------------------------
SELECT `Regiao`,
       MEASURE(`% Returns`)   AS return_rate,
       MEASURE(`Returns`)     AS returns_value,
       MEASURE(`Gross Sales`) AS gross_sales
FROM hpn.`4_semantic`.mv_comercial
GROUP BY `Regiao`
ORDER BY return_rate DESC;

-- -----------------------------------------------------------------------------
-- P: Quantos clientes ativos tivemos por tipo de negócio?
-- GUIA: `Customers Current` conta clientes DISTINTOS (quantidade inteira, não monetário).
-- -----------------------------------------------------------------------------
SELECT `TipoNegocio`,
       MEASURE(`Customers Current`) AS clientes_ativos,
       MEASURE(`Net Sales`)         AS net_sales
FROM hpn.`4_semantic`.mv_comercial
GROUP BY `TipoNegocio`
ORDER BY clientes_ativos DESC;

-- -----------------------------------------------------------------------------
-- P: Como foi a evolução das vendas mês a mês? / Qual o crescimento MoM e YoY?
-- GUIA: Use SEMPRE que a pergunta for sobre crescimento, tendência ou variação ao
--       longo do tempo (mês a mês / ano a ano). Para totais por ano SEM variação %,
--       prefira a metric view (dimensão `Ano`). NÃO calcule variação na metric view.
-- -----------------------------------------------------------------------------
SELECT year_month,      -- YYYYMM
       gross_sales,
       mom_pct,
       yoy_pct
FROM hpn.`4_semantic`.v_sales_time_intelligence
ORDER BY year_month;

-- -----------------------------------------------------------------------------
-- P: Qual foi o crescimento de vendas ano a ano (YoY) mais recente?
-- GUIA: Time intelligence, último mês disponível. Dados são históricos — "mais
--       recente" = maior year_month do dataset, não a data de hoje.
-- -----------------------------------------------------------------------------
SELECT year_month,
       gross_sales,
       yoy_pct
FROM hpn.`4_semantic`.v_sales_time_intelligence
ORDER BY year_month DESC
LIMIT 1;

-- -----------------------------------------------------------------------------
-- P: Quantos clientes temos em cada segmento RFM?
-- GUIA: Segmentação de clientes (Champions, At Risk, Lost...). Fonte = dim_customer_rfm.
-- -----------------------------------------------------------------------------
SELECT segment,
       COUNT(*)             AS qtd_clientes,
       SUM(gross_sales_12m) AS gross_sales_12m
FROM hpn.`4_semantic`.dim_customer_rfm
GROUP BY segment
ORDER BY qtd_clientes DESC;

-- -----------------------------------------------------------------------------
-- P: Quais clientes estão no segmento "At Risk"? / Liste os clientes <segmento>.
-- GUIA: Lista clientes de UM segmento RFM com nome. Usa o JOIN 1 (RFM -> transações).
--       O Genie injeta o segmento pedido em :segmento.
-- PARAM: segmento (STRING) — ex.: 'At Risk', 'Champions', 'Lost', 'Loyal Customers'
-- -----------------------------------------------------------------------------
SELECT DISTINCT t.customer_name,
       rfm.recency_days,
       rfm.sales_orders_12m,
       rfm.gross_sales_12m,
       rfm.segment
FROM hpn.`4_semantic`.dim_customer_rfm rfm
JOIN hpn.`4_semantic`.v_sales_transactions t
  ON t.customer_key = rfm.customer_key
WHERE rfm.segment = :segmento
ORDER BY rfm.gross_sales_12m DESC;

-- -----------------------------------------------------------------------------
-- P: Qual o preço unitário médio e o custo unitário médio por categoria?
-- GUIA: Measures de média (Avg Unit Price / Avg Unit Cost).
-- -----------------------------------------------------------------------------
SELECT `Categoria`,
       MEASURE(`Avg Unit Price`) AS preco_medio,
       MEASURE(`Avg Unit Cost`)  AS custo_medio
FROM hpn.`4_semantic`.mv_comercial
GROUP BY `Categoria`
ORDER BY preco_medio DESC;

-- -----------------------------------------------------------------------------
-- P: Vendas líquidas e margem bruta por ano
-- GUIA: Série anual simples via dimensão `Ano` da metric view. Para variação % ano a
--       ano use a view de time intelligence.
-- -----------------------------------------------------------------------------
SELECT `Ano`,
       MEASURE(`Net Sales`)    AS net_sales,
       MEASURE(`Gross Margin`) AS gross_margin
FROM hpn.`4_semantic`.mv_comercial
GROUP BY `Ano`
ORDER BY `Ano`;
