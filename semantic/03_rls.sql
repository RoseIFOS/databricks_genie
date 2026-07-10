-- =============================================================================
-- GOVERNANÇA — RLS regional + grants por domínio
-- Replica a RLS do Power BI: role Region -> auxRLS[Email] = USERPRINCIPALNAME()
-- Aqui a segurança é do MOTOR (Unity Catalog) e o Genie a herda automaticamente.
-- =============================================================================
USE CATALOG hpn_prd;

-- -----------------------------------------------------------------------------
-- 1) Tabela de mapeamento email -> região (substitui auxRLS)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS semantic.map_rls_region (
    email  STRING COMMENT 'UPN/email do usuário (current_user()).',
    region STRING COMMENT 'Região que o usuário pode enxergar.'
);
COMMENT ON TABLE semantic.map_rls_region IS
  'Mapa de acesso regional por usuário (equivalente à tabela auxRLS do Power BI).';

-- Ex.: INSERT INTO semantic.map_rls_region VALUES ('vendedor.sul@hpn.com', 'Sul');

-- -----------------------------------------------------------------------------
-- 2) Função de Row Filter — admin vê tudo; demais só sua(s) região(ões)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION semantic.rls_region(region STRING)
RETURNS BOOLEAN
COMMENT 'Row filter regional. TRUE se admin ou se a região pertence ao usuário logado.'
RETURN
    is_account_group_member('grp_admin')
    OR region IN (
        SELECT region FROM semantic.map_rls_region WHERE email = current_user()
    );

-- Aplica o filtro nas tabelas que carregam a coluna region (direta ou via join).
ALTER TABLE gold.dim_customer SET ROW FILTER semantic.rls_region ON (region);

-- -----------------------------------------------------------------------------
-- 3) Column mask de PII (ex.: dados de contato) para não-admins
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION semantic.mask_pii(v STRING)
RETURNS STRING
RETURN CASE WHEN is_account_group_member('grp_admin') THEN v ELSE '***' END;

-- Exemplo (ajuste às colunas reais de PII):
-- ALTER TABLE gold.dim_customer ALTER COLUMN email_contato SET MASK semantic.mask_pii;

-- -----------------------------------------------------------------------------
-- 4) Grants por domínio (comercial x financeiro x admin)
-- -----------------------------------------------------------------------------
-- Comercial: acesso ao schema gold (comercial) e ao metric view comercial.
GRANT USE SCHEMA ON SCHEMA gold      TO `grp_comercial`;
GRANT SELECT     ON TABLE  gold.v_sales_txn          TO `grp_comercial`;
GRANT SELECT     ON TABLE  semantic.mv_comercial     TO `grp_comercial`;
GRANT SELECT     ON TABLE  semantic.dim_customer_rfm TO `grp_comercial`;

-- Financeiro: acesso APENAS ao domínio financeiro.
GRANT USE SCHEMA ON SCHEMA gold      TO `grp_financeiro`;
GRANT SELECT     ON TABLE  gold.fct_finance          TO `grp_financeiro`;
GRANT SELECT     ON TABLE  semantic.mv_financeiro    TO `grp_financeiro`;

-- Admin: tudo.
GRANT ALL PRIVILEGES ON CATALOG hpn_prd TO `grp_admin`;

-- IMPORTANTE: comercial NÃO recebe grant no mv_financeiro e vice-versa.
-- Assim o Genie Comercial nunca acessa DRE, e o Financeiro nunca acessa vendas detalhadas.
