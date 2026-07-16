-- =============================================================================
-- PVM — Decomposição Preço × Volume × Mix (Fase 6, Passo 3)
-- Gera `hpn.ml.pvm_drivers`: explica a VARIAÇÃO de receita entre dois meses,
-- separando quanto veio de PREÇO, de VOLUME e de MIX (mudança de composição).
-- NÃO é ML e NÃO é inferência causal — é aritmética de decomposição de variância.
-- (O runbook chamava isto de "causal_drivers"; renomeado p/ pvm_drivers por
-- honestidade: cortamos o DoWhy/EconML. Ver ml/RUNBOOK_ml.md, Passo 3.)
--
-- Por que PVM e não causalidade: o Genie já responde "ONDE" a margem/receita mexeu
-- (decomposição descritiva). O valor desta tabela é dar a ele UMA convenção fixa e
-- correta, pra ele não inventar um SQL de decomposição diferente a cada pergunta.
--
-- -----------------------------------------------------------------------------
-- DECISÕES DE DESIGN (registradas a pedido)
-- -----------------------------------------------------------------------------
-- 1) GRÃO = SUBCATEGORIA (dim_product.subcategory_name). Mix só faz sentido sobre
--    alguma dimensão; subcategoria é o nível legível pra suplemento (conta a
--    história "migrou de creatina barata p/ whey caro"). Some p/ categoria/total.
-- 2) MENSAL, NÃO CRAVADO NO MÊS ATUAL: decompõe TODOS os meses do histórico. A
--    coluna `comparison_type` traz DUAS bases: 'MoM' (mês anterior) e 'YoY' (mesmo
--    mês do ano passado — tira a sazonalidade). Você analisa qualquer mês.
-- 3) "PREÇO" = preço médio REALIZADO por subcategoria no mês = receita/quantidade
--    (mistura os produtos da subcategoria — correto neste grão).
-- 4) MIX = RESÍDUO (delta_revenue − volume − price). Escolha deliberada porque:
--    (a) GARANTE que os 3 efeitos fechem EXATAMENTE na variação de receita (sem
--        sobra), por construção;
--    (b) ABSORVE subcategoria nova/descontinuada sem quebrar a conta (subcat nova
--        não tem preço-base p/ comparar → sua receita inteira cai no mix).
--    Trade-off: o mix vira um pouco "caixa-preta" (composição real + entradas/
--    saídas). Aceitável p/ suplemento, onde subcategoria raramente some mês a mês.
--
-- -----------------------------------------------------------------------------
-- FÓRMULAS (comparando mês atual [1] vs base [0]; Q = qtd total do mês, s = subcat)
--   p0_s = rev0_s/q0_s ; p1_s = rev1_s/q1_s ; avg_p0 = R0/Q0 ; mix_share0_s = q0_s/Q0
--   effect_volume_s = (Q1 − Q0) × mix_share0_s × avg_p0   -- cota da subcat no
--                       crescimento de VOLUME total, ao preço médio base
--   effect_price_s  = q1_s × (p1_s − p0_s)                -- variação de PREÇO no
--                       volume atual (0 se subcat nova/saída: sem preço p/ comparar)
--   effect_mix_s    = delta_revenue_s − effect_volume_s − effect_price_s  -- RESÍDUO
--   => Σ_s (volume + price + mix) = R1 − R0  (fecha exato — validado no check abaixo)
--
-- Catálogo `hpn` fixo (igual à camada semântica); gross_sales é DECIMAL no gold →
-- CAST p/ DOUBLE (mesma pegadinha do forecast: aritmética com Decimal quebra).
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS hpn.ml;

CREATE OR REPLACE TABLE hpn.ml.pvm_drivers AS
WITH sc AS (                                    -- subcategoria × mês
    SELECT
        date_trunc('month', s.order_date)                AS ms,
        COALESCE(p.subcategory_name, 'Sem subcategoria') AS subcategory,
        SUM(s.order_quantity)                            AS qty,
        SUM(CAST(s.gross_sales AS DOUBLE))               AS rev
    FROM hpn.`3_gold`.fct_sales_details s
    JOIN hpn.`3_gold`.dim_product p ON s.product_key = p.product_key
    GROUP BY date_trunc('month', s.order_date), COALESCE(p.subcategory_name, 'Sem subcategoria')
),
tt AS (                                         -- totais do mês (todas subcategorias)
    SELECT ms, SUM(qty) AS q_tot, SUM(rev) AS r_tot FROM sc GROUP BY ms
),
cmp(comparison_type, months_back) AS (          -- as duas bases de comparação
    VALUES ('MoM', 1), ('YoY', 12)
),
months AS (                                     -- meses atuais que possuem base
    SELECT c.comparison_type, tc.ms AS cur_ms, add_months(tc.ms, -c.months_back) AS base_ms
    FROM tt tc CROSS JOIN cmp c
    WHERE EXISTS (SELECT 1 FROM tt tb WHERE tb.ms = add_months(tc.ms, -c.months_back))
),
keys AS (                                       -- UNIÃO das subcats do mês atual OU do base
    SELECT m.comparison_type, m.cur_ms, m.base_ms, k.subcategory
    FROM months m
    JOIN sc k ON k.ms = m.cur_ms OR k.ms = m.base_ms
    GROUP BY m.comparison_type, m.cur_ms, m.base_ms, k.subcategory
),
paired AS (                                     -- alinha atual × base (0 onde faltar)
    SELECT
        k.comparison_type,
        k.cur_ms                        AS month_start,
        k.subcategory,
        COALESCE(cur.qty, 0)            AS q1,
        COALESCE(cur.rev, 0)            AS rev1,
        COALESCE(bse.qty, 0)            AS q0,
        COALESCE(bse.rev, 0)            AS rev0,
        tc.q_tot                        AS q_tot1,
        tc.r_tot                        AS r_tot1,
        tb.q_tot                        AS q_tot0,
        tb.r_tot                        AS r_tot0
    FROM keys k
    JOIN tt tc ON tc.ms = k.cur_ms
    JOIN tt tb ON tb.ms = k.base_ms
    LEFT JOIN sc cur ON cur.ms = k.cur_ms  AND cur.subcategory = k.subcategory
    LEFT JOIN sc bse ON bse.ms = k.base_ms AND bse.subcategory = k.subcategory
)
SELECT
    comparison_type,
    year(month_start) * 100 + month(month_start)          AS year_month,   -- YYYYMM
    month_start,
    subcategory,
    (rev1 - rev0)                                          AS delta_revenue,
    -- VOLUME: cota da subcat no crescimento de volume total, ao preço médio base
    CASE WHEN q_tot0 = 0 THEN 0
         ELSE (q_tot1 - q_tot0) * (q0 / q_tot0) * (r_tot0 / q_tot0) END
                                                           AS effect_volume,
    -- PREÇO: variação de preço realizado, no volume atual (0 se subcat nova/saída)
    CASE WHEN q0 = 0 OR q1 = 0 THEN 0
         ELSE q1 * ((rev1 / q1) - (rev0 / q0)) END
                                                           AS effect_price,
    -- MIX: resíduo → garante fechamento exato (delta = volume + price + mix)
    (rev1 - rev0)
      - (CASE WHEN q_tot0 = 0 THEN 0
              ELSE (q_tot1 - q_tot0) * (q0 / q_tot0) * (r_tot0 / q_tot0) END)
      - (CASE WHEN q0 = 0 OR q1 = 0 THEN 0
              ELSE q1 * ((rev1 / q1) - (rev0 / q0)) END)
                                                           AS effect_mix,
    current_timestamp()                                    AS _generated_at
FROM paired;

COMMENT ON TABLE hpn.ml.pvm_drivers IS
  'Decomposição Preço x Volume x Mix da variação de receita por subcategoria e mês. comparison_type = MoM (mês anterior) ou YoY (ano anterior). effect_volume + effect_price + effect_mix = delta_revenue (mix é resíduo, fecha exato). Use para "por que a receita subiu/caiu em <mês>".';

-- =============================================================================
-- VALIDAÇÃO (rodar após criar a tabela)
-- =============================================================================
-- 1) FECHAMENTO: a soma dos 3 efeitos tem que bater com a variação real. Deve
--    retornar 0 linhas (tolerância de centavo p/ ponto flutuante).
-- SELECT comparison_type, year_month,
--        round(SUM(effect_volume + effect_price + effect_mix), 2) AS soma_efeitos,
--        round(SUM(delta_revenue), 2)                             AS delta_real
-- FROM hpn.ml.pvm_drivers
-- GROUP BY comparison_type, year_month
-- HAVING abs(soma_efeitos - delta_real) > 0.01;
--
-- 2) LEITURA: por que a receita mudou num mês (ex.: YoY de 2026-06)?
-- SELECT subcategory, round(delta_revenue,0) AS delta,
--        round(effect_volume,0) AS vol, round(effect_price,0) AS preco,
--        round(effect_mix,0) AS mix
-- FROM hpn.ml.pvm_drivers
-- WHERE comparison_type = 'YoY' AND year_month = 202606
-- ORDER BY abs(delta_revenue) DESC;
-- =============================================================================
