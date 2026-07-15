-- =============================================================================
-- GOVERNANÇA — RLS regional + column mask + grants por domínio
-- Replica a RLS regional do Power BI (role Region -> auxRLS[Email]=USERPRINCIPALNAME()),
-- mas aqui a segurança é do MOTOR (Unity Catalog): o Genie e qualquer consulta a
-- herdam automaticamente.
--
-- Catálogo `hpn`; schemas `3_gold` / `4_semantic` (dígito inicial -> backtick).
--
-- ⚠️ ORDEM E RISCO: os comandos que ANEXAM o filtro/máscara (ROW FILTER / SET MASK)
--    estão COMENTADOS de propósito. Eles "trancam" o acesso — só rode-os quando:
--    (1) os grupos de conta existirem, (2) você estiver em `grp_admin`, e (3) o mapa
--    estiver populado. Siga o runbook: RUNBOOK_rls.md. Este arquivo é a fonte;
--    a ordem de execução vive no runbook.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Tabela de mapeamento email -> região (substitui a auxRLS do Power BI)
--    region deve casar com hpn.`3_gold`.dim_geography.region_name.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hpn.`4_semantic`.map_rls_region (
    email  STRING COMMENT 'UPN/email do usuário (igual ao current_user()).',
    region STRING COMMENT 'Região que o usuário pode enxergar (= dim_geography.region_name).'
);
COMMENT ON TABLE hpn.`4_semantic`.map_rls_region IS
  'Mapa de acesso regional por usuário (equivalente à tabela auxRLS do Power BI).';

-- Ex.: INSERT INTO hpn.`4_semantic`.map_rls_region VALUES ('vendedor.sul@bix.com', 'South');

-- -----------------------------------------------------------------------------
-- 2) Função de Row Filter — admin vê tudo; demais só a(s) sua(s) região(ões).
--    Anexada em dim_geography.region_name (o comercial junta geografia p/ vendas
--    E devoluções, então filtrar a geografia restringe os dois fatos de uma vez).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hpn.`4_semantic`.rls_region(region_name STRING)
RETURNS BOOLEAN
COMMENT 'Row filter regional. TRUE se admin ou se a região pertence ao usuário logado.'
RETURN
    is_account_group_member('grp_admin')
    OR region_name IN (
        SELECT region FROM hpn.`4_semantic`.map_rls_region
        WHERE email = current_user()
    );

-- -----------------------------------------------------------------------------
-- 3) Column mask (opcional) — dado sensível para não-admins.
--    OBS: dim_customer NÃO tem PII de contato (email/telefone). O campo comercialmente
--    sensível é annual_revenue (numérico) -> máscara devolve NULL p/ não-admin.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hpn.`4_semantic`.mask_revenue(v DECIMAL(18,2))
RETURNS DECIMAL(18,2)
COMMENT 'Mascara valor sensível: admin vê o valor; demais recebem NULL.'
RETURN CASE WHEN is_account_group_member('grp_admin') THEN v ELSE NULL END;

-- -----------------------------------------------------------------------------
-- 4) Grants por domínio (comercial x financeiro x admin)
--    Só rodar quando os grupos existirem. Concede acesso aos OBJETOS SEMÂNTICOS
--    (metric view + view plana + trusted assets), NÃO às tabelas gold cruas —
--    assim o comercial nunca enxerga a DRE e vice-versa (isolamento por domínio).
--    Depende de UC ownership chaining (as views e o gold têm o mesmo owner);
--    se precisar de acesso direto ao gold, conceda tabela a tabela POR DOMÍNIO,
--    nunca SELECT no schema `3_gold` inteiro (vazaria finance para o comercial).
-- -----------------------------------------------------------------------------
-- Navegação (todos os grupos precisam):
GRANT USE CATALOG ON CATALOG hpn                       TO `grp_comercial`;
GRANT USE SCHEMA  ON SCHEMA  hpn.`3_gold`              TO `grp_comercial`;
GRANT USE SCHEMA  ON SCHEMA  hpn.`4_semantic`          TO `grp_comercial`;
-- Comercial: metric view + view plana + trusted assets comerciais.
GRANT SELECT  ON TABLE    hpn.`4_semantic`.mv_comercial              TO `grp_comercial`;
GRANT SELECT  ON TABLE    hpn.`4_semantic`.v_sales_transactions      TO `grp_comercial`;
GRANT SELECT  ON TABLE    hpn.`4_semantic`.dim_customer_rfm          TO `grp_comercial`;
GRANT SELECT  ON VIEW     hpn.`4_semantic`.v_sales_time_intelligence TO `grp_comercial`;
GRANT EXECUTE ON FUNCTION hpn.`4_semantic`.customer_segment          TO `grp_comercial`;

GRANT USE CATALOG ON CATALOG hpn                       TO `grp_financeiro`;
GRANT USE SCHEMA  ON SCHEMA  hpn.`3_gold`              TO `grp_financeiro`;
GRANT USE SCHEMA  ON SCHEMA  hpn.`4_semantic`          TO `grp_financeiro`;
-- Financeiro: APENAS o domínio financeiro.
GRANT SELECT ON TABLE hpn.`4_semantic`.mv_financeiro      TO `grp_financeiro`;
GRANT SELECT ON TABLE hpn.`4_semantic`.v_income_statement TO `grp_financeiro`;

-- Admin: tudo.
GRANT ALL PRIVILEGES ON CATALOG hpn TO `grp_admin`;

-- IMPORTANTE: comercial NÃO recebe grant no mv_financeiro e vice-versa. Assim o
-- Genie Comercial nunca acessa a DRE, e o Financeiro nunca acessa vendas detalhadas.

-- =============================================================================
-- 5) APLICAÇÃO DO FILTRO/MÁSCARA  ⚠️  RODAR POR ÚLTIMO (trancam o acesso)
--    Descomente e execute só depois de: grupos criados + você no grp_admin +
--    mapa populado. Ver RUNBOOK_rls.md.
-- =============================================================================
-- ALTER TABLE hpn.`3_gold`.dim_geography
--   SET ROW FILTER hpn.`4_semantic`.rls_region ON (region_name);
--
-- ALTER TABLE hpn.`3_gold`.dim_customer
--   ALTER COLUMN annual_revenue SET MASK hpn.`4_semantic`.mask_revenue;

-- Rollback (se precisar destravar):
-- ALTER TABLE hpn.`3_gold`.dim_geography DROP ROW FILTER;
-- ALTER TABLE hpn.`3_gold`.dim_customer ALTER COLUMN annual_revenue DROP MASK;
-- =============================================================================
