-- =============================================================================
-- RECOMENDAÇÃO — Next-Best-Action por cliente (Fase 6, Passo 2)
-- Gera a tabela `hpn.ml.reco_customer_actions` a partir da segmentação RFM
-- (`hpn.4_semantic.dim_customer_rfm`, Fase 3.3). NÃO é modelo de ML: são regras
-- por segmento — simples, explicáveis e alinhadas ao playbook de RFM. O Genie e o
-- App leem esta TABELA (mesmo princípio da Fase 6: "análise avançada é só + 1 tabela").
--
-- NICHO: Heavy Power Nutrition = loja de SUPLEMENTOS (whey, caseína, mass gainer,
-- BCAA/creatina/pré-treino, snacks, apparel). Suplemento é consumível de reposição
-- previsível (~1 mês/pote) → `recency_days` é sinal forte de RECOMPRA/lapso, e
-- recorrência/assinatura é jogada central (não faria sentido pra bem durável).
--
-- RESSALVA: o site HOJE não tem assinatura nem programa de fidelidade. Táticas que
-- dependem disso (assinatura, VIP) são OPORTUNIDADES A CRIAR, não alavancas prontas
-- — sinalizado no `rationale`. As acionáveis já: lembrete de reposição, desconto
-- direcionado, cross-sell/bundle.
--
-- Catálogo `hpn` fixo (igual aos arquivos da camada semântica); na promoção dev→prd
-- (Fase 10) o Asset Bundle troca o catálogo. Schema `ml` não tem dígito inicial → sem
-- backtick; `4_semantic` exige backtick.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS hpn.ml;

CREATE OR REPLACE TABLE hpn.ml.reco_customer_actions AS
-- Mapa segmento → (intenção estratégica, tática que casa com suplemento, justificativa,
-- prioridade-base). A INTENÇÃO vale em qualquer nicho; a TÁTICA é específica de suplemento.
WITH action_map(segment, intent, suggested_lever, rationale, base_priority) AS (
    VALUES
        ('Champions',           'Reter & expandir',        'Assinatura dos itens core (whey/creatina), acesso VIP a lançamentos, pedir indicação', 'Melhores clientes: recompra recente e alto valor. Reter e ampliar ticket. (Assinatura/VIP = capacidade a criar.)', 'Alta'),
        ('Cant Lose Them',      'Reconquistar (urgente)',  'Contato direto (1:1) + oferta forte na recompra dos produtos habituais',               'Eram muito valiosos e sumiram. Risco alto de perda definitiva.',                                                    'Alta'),
        ('At Risk',             'Reconquistar',            'Lembrete de reposição + desconto no reabastecimento dos itens usuais',                 'Bom histórico, recência caindo: provável que o pote acabou e não voltou.',                                          'Alta'),
        ('Loyal Customers',     'Expandir',                'Cross-sell de stack (quem toma whey -> creatina/pré-treino), assinatura',              'Compram com constância. Crescer categorias e fixar recompra.',                                                      'Média'),
        ('Potential Loyalist',  'Desenvolver / fidelizar', 'Empurrar 2ª/3ª compra, bundle proteína + coqueteleira, apresentar assinatura',         'Recentes e promissores. Consolidar o hábito de recompra.',                                                          'Média'),
        ('Needing Attention',   'Reengajar',               'Lembrete "seu estoque acabou?" + oferta por tempo limitado',                           'Frequência/valor médios com recência em queda. Reativar antes de esfriar.',                                         'Média'),
        ('About to Sleep',      'Reengajar',               'Win-back leve: cupom de reabastecimento',                                              'Recência baixa. Janela curta antes de virar inativo.',                                                              'Média'),
        ('New Customers',       'Onboarding',              'Educar sobre uso/stack + cupom para a 2ª compra',                                      'Compra recente, ainda sem hábito. Converter em recorrente.',                                                        'Média'),
        ('Promising',           'Nutrir',                  'Conteúdo + oferta para aumentar a frequência',                                         'Recência ok, mas baixa frequência/valor. Desenvolver.',                                                             'Baixa'),
        ('Hibernating',         'Reativar barato ou soltar','Campanha de e-mail/oferta de baixo custo',                                            'Inativos de baixo engajamento. Investir pouco.',                                                                    'Baixa'),
        ('Lost',                'Desprioritizar',          'Só em campanha ampla de winback',                                                      'Sem recência e baixo engajamento. Menor ROI de esforço.',                                                           'Baixa')
)
SELECT
    r.customer_key,
    r.segment,
    am.intent,
    am.suggested_lever,
    am.rationale,
    -- PRIORIDADE (b): parte da prioridade-base do segmento e SOBE um nível se o cliente
    -- é de alto valor (score monetário M >= 4, i.e. gross_sales_12m >= 200k na RFM).
    -- Foca o esforço comercial onde há mais dinheiro em jogo.
    CASE
        WHEN am.base_priority = 'Alta'                    THEN 'Alta'
        WHEN am.base_priority = 'Média' AND r.m >= 4      THEN 'Alta'
        WHEN am.base_priority = 'Baixa' AND r.m >= 4      THEN 'Média'
        ELSE am.base_priority
    END                                        AS priority,
    -- Contexto para ordenar/filtrar (ex.: "At Risk de maior valor primeiro").
    r.recency_days,
    r.sales_orders_12m,
    r.gross_sales_12m,
    current_timestamp()                        AS _generated_at
FROM hpn.`4_semantic`.dim_customer_rfm r
LEFT JOIN action_map am ON r.segment = am.segment;

COMMENT ON TABLE hpn.ml.reco_customer_actions IS
  'Next-best-action por cliente (regras sobre RFM). Colunas: segment, intent (intenção estratégica), suggested_lever (tática p/ suplemento), rationale, priority (Alta/Média/Baixa, ponderada por valor). Use para "o que fazer com clientes X" e priorização de esforço comercial. Refresh via Lakeflow Job.';
