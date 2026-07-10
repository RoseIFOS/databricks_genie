"""
Persistência do estado do app em LakeBase (Postgres gerenciado do Databricks).
Guarda histórico de conversas e feedback -> insumo para curar o Genie.

O token de acesso ao LakeBase é gerado pelo SDK (OAuth) e usado como senha do
Postgres. Host/DB vêm de variáveis de ambiente (app.yaml).
"""
from __future__ import annotations

import os
import psycopg
from databricks.sdk import WorkspaceClient

_w = WorkspaceClient()


def _conn() -> psycopg.Connection:
    # Gera credencial de curta duração para o Postgres do LakeBase.
    cred = _w.database.generate_database_credential(
        request_id="hpn-app", instance_names=[os.environ["LAKEBASE_HOST"].split(".")[0]]
    )
    return psycopg.connect(
        host=os.environ["LAKEBASE_HOST"],
        dbname=os.environ["LAKEBASE_DB"],
        user=_w.current_user.me().user_name,
        password=cred.token,
        sslmode="require",
        autocommit=True,
    )


DDL = """
CREATE TABLE IF NOT EXISTS conversations (
    id            BIGSERIAL PRIMARY KEY,
    user_name     TEXT NOT NULL,
    domain        TEXT NOT NULL,          -- 'comercial' | 'financeiro'
    genie_conv_id TEXT,
    created_at    TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS messages (
    id            BIGSERIAL PRIMARY KEY,
    conversation  BIGINT REFERENCES conversations(id),
    role          TEXT NOT NULL,          -- 'user' | 'assistant'
    content       TEXT,
    sql           TEXT,
    created_at    TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS feedback (
    id            BIGSERIAL PRIMARY KEY,
    message       BIGINT REFERENCES messages(id),
    rating        SMALLINT,               -- +1 / -1
    comment       TEXT,
    created_at    TIMESTAMPTZ DEFAULT now()
);
"""


def init_schema() -> None:
    with _conn() as c:
        c.execute(DDL)


def log_message(user_name: str, domain: str, role: str,
                content: str, sql: str | None = None,
                genie_conv_id: str | None = None) -> int:
    with _conn() as c:
        conv = c.execute(
            "INSERT INTO conversations(user_name, domain, genie_conv_id) "
            "VALUES (%s,%s,%s) RETURNING id",
            (user_name, domain, genie_conv_id),
        ).fetchone()[0]
        msg = c.execute(
            "INSERT INTO messages(conversation, role, content, sql) "
            "VALUES (%s,%s,%s,%s) RETURNING id",
            (conv, role, content, sql),
        ).fetchone()[0]
        return msg


def log_feedback(message_id: int, rating: int, comment: str | None = None) -> None:
    with _conn() as c:
        c.execute(
            "INSERT INTO feedback(message, rating, comment) VALUES (%s,%s,%s)",
            (message_id, rating, comment),
        )
