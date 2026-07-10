-- =============================================================================
-- CAMADA SEMÂNTICA — Views gold de consumo
-- Base para os Metric Views. Resolve o cruzamento de fatos (vendas x devoluções)
-- com uma view transacional unificada, evitando fanout de join.
-- =============================================================================

-- Padrão: catálogo por ambiente (hpn_dev / hpn_prd). Ajuste o USE conforme o alvo.
USE CATALOG hpn_prd;

-- -----------------------------------------------------------------------------
-- 1) View transacional unificada de vendas + devoluções
--    Cada linha é uma transação (sale ou return) no MESMO grão dimensional
--    (data, cliente, produto). Isso permite Gross Sales, Returns e Net Sales
--    coexistirem em um único Metric View sem duplicar linhas.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW gold.v_sales_txn AS
SELECT
    'sale'                              AS txn_type,
    sales_order_number,
    order_date                          AS date_id,
    customer_key,
    product_key,
    order_quantity                      AS quantity,
    unit_price,
    unit_cost,
    discount_amount,
    order_quantity * unit_price         AS amount        -- valor bruto da linha
FROM gold.fct_sales_details

UNION ALL

SELECT
    'return'                            AS txn_type,
    sales_order_number,
    order_date                          AS date_id,
    customer_key,
    product_key,
    return_quantity                     AS quantity,
    unit_price,
    CAST(0 AS DOUBLE)                   AS unit_cost,
    CAST(0 AS DOUBLE)                   AS discount_amount,
    return_quantity * unit_price        AS amount        -- valor devolvido
FROM gold.fct_sales_returns;

COMMENT ON VIEW gold.v_sales_txn IS
  'Transações comerciais unificadas (venda/devolução) no grão data-cliente-produto. Fonte do metric view comercial.';

-- -----------------------------------------------------------------------------
-- 2) Documentação de negócio (COMMENT) — pré-requisito para qualidade do Genie
--    Repita o padrão para TODAS as colunas relevantes.
-- -----------------------------------------------------------------------------
COMMENT ON TABLE gold.fct_sales_details IS
  'Detalhe de vendas por item de pedido. Grão: linha de pedido (sales_order_number x product_key).';
COMMENT ON TABLE gold.fct_sales_returns IS
  'Devoluções de vendas por item. Grão: linha de devolução.';
COMMENT ON TABLE gold.fct_finance IS
  'Lançamentos financeiros (DRE). Coluna scenario distingue realizado (actual) de orçado (budget).';
COMMENT ON TABLE gold.dim_customer IS
  'Cadastro de clientes. Coluna region governa a RLS regional.';
COMMENT ON TABLE gold.dim_product IS
  'Cadastro de produtos com hierarquia categoria > subcategoria > produto.';
COMMENT ON TABLE gold.dim_account IS
  'Plano de contas. sign (+1/-1) define o efeito do lançamento no resultado.';

ALTER TABLE gold.fct_sales_details ALTER COLUMN unit_price
  COMMENT 'Preço unitário de venda (USD).';
ALTER TABLE gold.fct_sales_details ALTER COLUMN unit_cost
  COMMENT 'Custo unitário do produto (USD).';
ALTER TABLE gold.fct_sales_details ALTER COLUMN discount_amount
  COMMENT 'Valor de desconto concedido na linha (USD).';
ALTER TABLE gold.fct_finance ALTER COLUMN scenario
  COMMENT 'Cenário do lançamento: "actual" (realizado) ou "budget" (orçado).';
ALTER TABLE gold.dim_account ALTER COLUMN sign
  COMMENT 'Sinal contábil (+1 receita / -1 despesa) aplicado ao amount para compor o resultado.';

-- -----------------------------------------------------------------------------
-- 3) Tags de governança (domínio + sensibilidade)
-- -----------------------------------------------------------------------------
ALTER TABLE gold.fct_sales_details SET TAGS ('domain' = 'comercial');
ALTER TABLE gold.fct_sales_returns SET TAGS ('domain' = 'comercial');
ALTER TABLE gold.dim_customer      SET TAGS ('domain' = 'comercial', 'pii' = 'true');
ALTER TABLE gold.dim_product       SET TAGS ('domain' = 'comercial');
ALTER TABLE gold.fct_finance       SET TAGS ('domain' = 'financeiro');
ALTER TABLE gold.dim_account       SET TAGS ('domain' = 'financeiro');
