import { defineConfig } from 'vite';

export default defineConfig({
  base: './', // Use relative paths for built assets
  build: {
    chunkSizeWarningLimit: 1000,
    outDir: '../assets/web',
    emptyOutDir: true,
    rollupOptions: {
      output: {
        entryFileNames: `[name].js`,
        chunkFileNames: `[name].js`,
        assetFileNames: `[name].[ext]`
      }
    }
  }
});
