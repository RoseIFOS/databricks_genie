CREATE OR REFRESH MATERIALIZED VIEW department_group
(
  CONSTRAINT valid_key EXPECT (department_group_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: department_group conformado (agrupamento de departamentos p/ o financeiro)'
AS
SELECT
  CAST(departmentgroupkey AS BIGINT) AS department_group_key,  -- chave; finance.department_group_key aponta p/ cá
  TRIM(departmentgroupname)          AS department_group_name,  -- nome do grupo de departamentos

  CAST(id AS BIGINT)                 AS _source_id,             -- id da origem (lineage + tiebreaker)
  current_timestamp()                AS _silver_loaded_at
FROM hpn.`1_bronze`.department_group
-- DEDUP: 1 linha por grupo (id maior = mais recente)
QUALIFY ROW_NUMBER() OVER (PARTITION BY departmentgroupkey ORDER BY id DESC) = 1;
