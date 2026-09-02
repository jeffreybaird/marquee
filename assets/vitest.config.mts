import { fileURLToPath } from "node:url"
import { defineConfig } from "vitest/config"

/**
 * Phoenix ships its JavaScript inside the Hex packages under `deps/`, not
 * through npm. esbuild finds them via NODE_PATH (see config/config.exs); the
 * test runner needs the same packages aliased to their ESM builds.
 */
const dep = (path: string): string =>
  fileURLToPath(new URL(`../deps/${path}`, import.meta.url))

export default defineConfig({
  resolve: {
    alias: {
      phoenix: dep("phoenix/priv/static/phoenix.mjs"),
      phoenix_live_view: dep("phoenix_live_view/priv/static/phoenix_live_view.esm.js"),
    },
  },
  test: {
    environment: "jsdom",
    include: ["test/**/*.test.ts"],
    restoreMocks: true,
  },
})
