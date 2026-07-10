"""
Wrapper da Genie Conversation API (Databricks SDK).

Responsável por: iniciar/continuar conversa em um Genie Space, aguardar a
resposta e normalizar o retorno em {texto, sql, dataframe}.

Autenticação:
- Por padrão usa o service principal do app (WorkspaceClient() sem args).
- Para respeitar a RLS por USUÁRIO (on-behalf-of), passe o token do usuário
  obtido do header 'x-forwarded-access-token' (ver app.py -> get_user_token()).
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field

import pandas as pd
from databricks.sdk import WorkspaceClient


@dataclass
class GenieAnswer:
    text: str = ""                       # resposta textual do Genie
    sql: str | None = None               # SQL gerado (transparência/observabilidade)
    dataframe: pd.DataFrame | None = None  # resultado tabular, se houver
    conversation_id: str | None = None   # para manter o contexto do chat
    error: str | None = None


class GenieClient:
    """Cliente de um Genie Space específico."""

    def __init__(self, space_id: str, user_token: str | None = None):
        self.space_id = space_id
        # OBO: se houver token do usuário, as consultas herdam a RLS dele.
        self.w = WorkspaceClient(token=user_token) if user_token else WorkspaceClient()

    def ask(self, question: str, conversation_id: str | None = None,
            timeout_s: int = 120) -> GenieAnswer:
        try:
            if conversation_id is None:
                msg = self.w.genie.start_conversation_and_wait(self.space_id, question)
                conversation_id = msg.conversation_id
            else:
                msg = self.w.genie.create_message_and_wait(
                    self.space_id, conversation_id, question
                )
            return self._parse(msg, conversation_id)
        except Exception as e:  # noqa: BLE001
            return GenieAnswer(error=str(e), conversation_id=conversation_id)

    # ------------------------------------------------------------------ #
    def _parse(self, msg, conversation_id: str) -> GenieAnswer:
        ans = GenieAnswer(conversation_id=conversation_id)
        attachments = getattr(msg, "attachments", None) or []

        for att in attachments:
            # Atributo textual
            if getattr(att, "text", None) and getattr(att.text, "content", None):
                ans.text += att.text.content

            # Atributo de consulta (SQL + resultado)
            query = getattr(att, "query", None)
            if query is not None:
                ans.sql = getattr(query, "query", None)
                if getattr(query, "description", None):
                    ans.text += (query.description or "")
                ans.dataframe = self._fetch_result(conversation_id, msg.id,
                                                    getattr(att, "attachment_id", None))
        if not ans.text and getattr(msg, "content", None):
            ans.text = msg.content
        return ans

    def _fetch_result(self, conversation_id: str, message_id: str,
                      attachment_id: str | None) -> pd.DataFrame | None:
        """Busca o resultado da query e devolve como DataFrame."""
        try:
            # SDKs recentes: por attachment; fallback: por mensagem.
            try:
                res = self.w.genie.get_message_attachment_query_result(
                    self.space_id, conversation_id, message_id, attachment_id
                )
            except Exception:  # noqa: BLE001
                res = self.w.genie.get_message_query_result(
                    self.space_id, conversation_id, message_id
                )

            statement = res.statement_response
            cols = [c.name for c in statement.manifest.schema.columns]
            rows = statement.result.data_array or []
            return pd.DataFrame(rows, columns=cols)
        except Exception:  # noqa: BLE001
            return None
