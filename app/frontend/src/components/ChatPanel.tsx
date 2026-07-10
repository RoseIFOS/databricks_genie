// Painel de chat de um domínio. Mantém histórico + conversation_id (contexto do
// Genie) e renderiza tabela de resultado, SQL gerado e botões de feedback.
import { useState } from "react";
import { sendChat, sendFeedback, ChatResponse } from "../api";

interface Message {
  role: "user" | "assistant";
  content: string;
  data?: ChatResponse;
}

export default function ChatPanel({ domain }: { domain: string }) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSend() {
    const question = input.trim();
    if (!question || loading) return;

    setMessages((m) => [...m, { role: "user", content: question }]);
    setInput("");
    setLoading(true);

    const resp = await sendChat(domain, question, conversationId);
    setLoading(false);

    if (resp.error) {
      setMessages((m) => [...m, { role: "assistant", content: `⚠️ Erro: ${resp.error}` }]);
      return;
    }
    setConversationId(resp.conversation_id ?? conversationId);
    setMessages((m) => [
      ...m,
      { role: "assistant", content: resp.text || "(sem resposta textual)", data: resp },
    ]);
  }

  return (
    <div className="chat">
      <div className="messages">
        {messages.map((m, i) => (
          <div key={i} className={`msg ${m.role}`}>
            <div className="bubble">{m.content}</div>
            {m.data && <ResultView data={m.data} />}
          </div>
        ))}
        {loading && <div className="msg assistant"><div className="bubble">Consultando o Genie…</div></div>}
      </div>

      <div className="composer">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleSend()}
          placeholder={`Pergunte aos dados de ${domain}...`}
        />
        <button onClick={handleSend} disabled={loading}>Enviar</button>
      </div>
    </div>
  );
}

// Renderiza o resultado: tabela + SQL (expansível) + análise avançada + feedback.
function ResultView({ data }: { data: ChatResponse }) {
  const [showSql, setShowSql] = useState(false);

  return (
    <div className="result">
      {data.columns.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>{data.columns.map((c) => <th key={c}>{c}</th>)}</tr>
            </thead>
            <tbody>
              {data.rows.slice(0, 100).map((row, ri) => (
                <tr key={ri}>{row.map((cell, ci) => <td key={ci}>{String(cell ?? "")}</td>)}</tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {data.advanced && (
        <div className="advanced">
          🔎 Análise <b>{data.advanced.intent}</b>
          <pre>{JSON.stringify(data.advanced.result, null, 2)}</pre>
        </div>
      )}

      {data.sql && (
        <div className="sql">
          <button className="link" onClick={() => setShowSql((s) => !s)}>
            {showSql ? "▼" : "▶"} SQL gerado
          </button>
          {showSql && <pre>{data.sql}</pre>}
        </div>
      )}

      {data.message_id != null && (
        <div className="feedback">
          <button onClick={() => sendFeedback(data.message_id!, 1)}>👍</button>
          <button onClick={() => sendFeedback(data.message_id!, -1)}>👎</button>
        </div>
      )}
    </div>
  );
}
