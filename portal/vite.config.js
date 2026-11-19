import { defineConfig } from 'vitest/config';
import { t } from './src/i18n.js';

const proxy = { '/api': 'http://localhost:8000' };

export default defineConfig({
  plugins: [
    {
      name: 'spanish-document-copy',
      transformIndexHtml(html) {
        // Trusted dictionary strings, never API-provided HTML.
        return html
          .replace('%PORTAL_TITLE%', `${t.appName} · ${t.portalTitle}`)
          .replace('%NO_SCRIPT%', t.noScript);
      },
    },
  ],
  server: { port: 5173, strictPort: true, proxy },
  preview: { port: 5173, strictPort: true, proxy },
  test: {
    environment: 'jsdom',
    include: ['tests/**/*.test.js'],
    clearMocks: true,
    restoreMocks: true,
  },
});
