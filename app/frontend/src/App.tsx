// Componente raiz: cabeçalho + duas abas (Comercial / Financeiro).
// Cada aba é um <ChatPanel> independente, apontando para seu domínio.
import { useEffect, useState } from "react";
import { getMe } from "./api";
import ChatPanel from "./components/ChatPanel";

const DOMAINS = [
  { key: "comercial", label: "🛒 Comercial" },
  { key: "financeiro", label: "💰 Financeiro" },
];

export default function App() {
  const [email, setEmail] = useState("...");
  const [active, setActive] = useState("comercial");

  useEffect(() => {
    getMe().then((m) => setEmail(m.email)).catch(() => setEmail("desconhecido"));
  }, []);

  return (
    <div className="app">
      <header className="header">
        <h1>📊 HPN • BI Conversacional</h1>
        <span className="user">{email}</span>
      </header>

      <nav className="tabs">
        {DOMAINS.map((d) => (
          <button
            key={d.key}
            className={active === d.key ? "tab active" : "tab"}
            onClick={() => setActive(d.key)}
          >
            {d.label}
          </button>
        ))}
      </nav>

      {/* Renderiza os dois painéis, mas só exibe o ativo (preserva o histórico
          de cada aba ao alternar). */}
      {DOMAINS.map((d) => (
        <div key={d.key} style={{ display: active === d.key ? "block" : "none" }}>
          <ChatPanel domain={d.key} />
        </div>
      ))}
    </div>
  );
}
