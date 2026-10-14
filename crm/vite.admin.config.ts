import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Админка Beepy — отдельная сборка из того же проекта: общий кит, свои
// страницы. Сервер отдаёт её по /admin (server/src/admin.ts), в разработке
// запросы к /admin/api уходят на локальный сервер.
export default defineConfig({
  base: '/admin/',
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  build: {
    outDir: 'dist-admin',
    emptyOutDir: true,
    rollupOptions: { input: path.resolve(__dirname, 'admin.html') },
  },
  server: {
    port: 5174,
    proxy: { '/admin/api': 'http://127.0.0.1:8787' },
  },
})
