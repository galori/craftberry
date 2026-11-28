import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// Tests live in server/test/appattest and use vitest globals, so they need no node_modules of their own.
export default defineConfig({
  root: fileURLToPath(new URL('../..', import.meta.url)),
  cacheDir: fileURLToPath(new URL('./node_modules/.vite', import.meta.url)),
  test: {
    globals: true,
    environment: 'node',
    include: ['test/appattest/**/*.test.ts'],
  },
});
