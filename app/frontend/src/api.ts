// Camada de acesso à API do backend FastAPI (../main.py).
// Todas as chamadas vão para /api/* — em DEV o Vite faz proxy para o FastAPI local.

export interface ChatResponse {
  text: string;
  sql?: string | null;
  columns: string[];
  rows: unknown[][];
  conversation_id?: string | null;
  advanced?: { intent: string; result: unknown } | null;
  message_id?: number | null;
  error?: string;
}

// Envia uma pergunta ao chat de um domínio ('comercial' | 'financeiro').
export async function sendChat(
  domain: string,
  question: string,
  conversationId: string | null
): Promise<ChatResponse> {
  const res = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      domain,
      question,
      conversation_id: conversationId,
    }),
  });
  return res.json();
}

// Registra feedback 👍/👎 de uma resposta.
export async function sendFeedback(messageId: number, rating: number): Promise<void> {
  await fetch("/api/feedback", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message_id: messageId, rating }),
  });
}

// Descobre o e-mail do usuário logado (para o cabeçalho).
export async function getMe(): Promise<{ email: string }> {
  const res = await fetch("/api/me");
  return res.json();
}
