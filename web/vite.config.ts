import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  // Relative asset paths. The built files are served by the app under a custom
  // scheme, not from a web root, so absolute "/assets/..." would not resolve.
  base: './',
  plugins: [react(), tailwindcss()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    // One CSS file keeps the load simple and avoids a flash of unstyled panel.
    cssCodeSplit: false,
    // Everything loads from disk in one go, so a single larger chunk beats
    // splitting. Raised past the default only to keep the build output quiet.
    chunkSizeWarningLimit: 700,
  },
  server: {
    port: 5173,
    strictPort: true,
  },
})
