# 02 — Governança de storage (External Locations + Volumes)

> Substitui: todo o capítulo *"Mount"* de *"Processamento com Databricks"* e a
> maior parte do *"Azure Key Vault"*.

## Por que os mounts saíram

No manual antigo você:
1. Pegava `client_id / tenant_id / client_secret` (App Registration) — no começo **hardcoded no notebook**, depois via Key Vault.
2. Montava conta OAuth: `fs.azure.account.oauth2.client.secret = ...`.
3. `dbutils.fs.mount(...)` para cada container → acessava via `/mnt/adlsolist/...`.

Problemas: o mount é **global no workspace** (qualquer notebook enxerga, sem
governança por usuário), o secret vive no ambiente, e não há lineage. Por isso
**mounts (`/mnt`) estão deprecados** para dados governados.

## O modelo novo (uma credencial, governada pelo UC)

```
Access Connector (managed identity)
      │  (tem "Storage Blob Data Contributor" no ADLS)
      ▼
Storage Credential (objeto no UC que aponta p/ o Access Connector)
      ▼
External Location (abfss://container@conta.dfs.core.windows.net/  +  credential)
      ├── tabelas externas / managed tables
      └── Volume (acesso a ARQUIVOS: /Volumes/cat/schema/vol/...)
```

Você configura **uma vez**. Ninguém mais mexe com client_secret, e o acesso é
auditado e concedível por `GRANT` no UC.

## Passo a passo

### 1. Dar permissão à managed identity (no portal Azure)
No **ADLS Gen2 → Access Control (IAM) → Add role assignment**:
- Role: **Storage Blob Data Contributor**
- Assign to: **Managed identity** → selecione o **Access Connector** criado no capítulo 01.

> É o mesmo papel do manual antigo (*Storage Blob Data Contributor*), mas agora
> atribuído à **managed identity do Access Connector**, não a um service principal.

### 2. Criar o Storage Credential (no Databricks)
**Catalog Explorer → External Data → Credentials → Create credential**
(tipo *Azure Managed Identity*, apontando para o resource ID do Access Connector).
Ou via SQL:

```sql
CREATE STORAGE CREDENTIAL cred_adls_hpn
  WITH (AZURE_MANAGED_IDENTITY = '<resource-id-do-access-connector>');
```

### 3. Criar as External Locations (uma por container/zona)
```sql
CREATE EXTERNAL LOCATION landing_zone
  URL 'abfss://landing@adlshpn.dfs.core.windows.net/'
  WITH (STORAGE CREDENTIAL cred_adls_hpn);

CREATE EXTERNAL LOCATION checkpoints
  URL 'abfss://checkpoints@adlshpn.dfs.core.windows.net/'
  WITH (STORAGE CREDENTIAL cred_adls_hpn);
```

### 4. Criar um Volume para os arquivos da landing
**Volumes** são o substituto governado do mount para acesso a arquivos
(o Auto Loader/`read_files` lê daqui no capítulo 04):

```sql
CREATE EXTERNAL VOLUME hpn_dev.bronze.landing
  LOCATION 'abfss://landing@adlshpn.dfs.core.windows.net/full_load';
```

Agora o caminho vira **`/Volumes/hpn_dev/bronze/landing/...`** — sem mount.

> **De → para:**
> `/mnt/adlsolist/1-landingzone/full_load/dbo_olist_customers_dataset.parquet`
> → `/Volumes/hpn_dev/bronze/landing/dbo_olist_customers_dataset.parquet`

### 5. Verificar
```python
display(dbutils.fs.ls('/Volumes/hpn_dev/bronze/landing/'))
```

## E o Key Vault?
Continua útil, mas o escopo encolheu:
- **Não precisa mais** para autenticar o ADLS (a managed identity resolve).
- **Ainda serve** para credenciais de **terceiros** — ex.: a senha do Postgres/Neon
  usada na ingestão (capítulo 03), se você não usar Lakeflow Connect.
- Prefira **Databricks-backed secret scopes** (ou scope respaldado por Key Vault)
  e nunca imprima o secret — `dbutils.secrets.get()` já vem `[REDACTED]`.

## Checklist de saída
- [ ] Access Connector com *Storage Blob Data Contributor* no ADLS.
- [ ] Storage Credential + External Locations (`landing`, `checkpoints`).
- [ ] Volume `hpn_dev.bronze.landing` acessível via `/Volumes/...`.
- [ ] Nenhum `dbutils.fs.mount` e nenhum `client_secret` em notebook.
