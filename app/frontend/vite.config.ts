import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Config do Vite.
// - build: gera 'dist/' que o FastAPI (../main.py) serve em produção.
// - server.proxy: em DEV (npm run dev), redireciona /api para o FastAPI local
//   (rode o back com: python main.py). Assim front e back conversam sem CORS.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:8000",
    },
  },
  build: {
    outDir: "dist",
  },
});
