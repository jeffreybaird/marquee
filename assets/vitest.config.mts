import { readFile } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import { defineConfig, type Plugin } from "vitest/config"

/**
 * Phoenix ships its JavaScript inside the Hex packages under `deps/`, not
 * through npm. esbuild finds them via NODE_PATH (see config/config.exs); the
 * test runner needs the same packages aliased to their ESM builds.
 */
const dep = (path: string): string =>
  fileURLToPath(new URL(`../deps/${path}`, import.meta.url))

/**
 * The vendored bundles end with `//# sourceMappingURL=` comments pointing at
 * map files that were never vendored. Vite reads those maps when it loads a
 * file itself and logs an ENOENT for each; serving the file from a load hook
 * with the comment stripped keeps the test output clean.
 */
const vendorWithoutSourceMapComments: Plugin = {
  name: "marquee:vendor-without-sourcemap-comments",
  async load(id) {
    if (!id.includes("/vendor/") || !id.endsWith(".js")) return null
    const code = await readFile(id, "utf8")
    return code.replace(/^\/\/# sourceMappingURL=.*$/gm, "")
  },
}

export default defineConfig({
  plugins: [vendorWithoutSourceMapComments],
  resolve: {
    alias: {
      phoenix: dep("phoenix/priv/static/phoenix.mjs"),
      phoenix_live_view: dep("phoenix_live_view/priv/static/phoenix_live_view.esm.js"),
    },
  },
  test: {
    environment: "jsdom",
    include: ["test/**/*.test.ts"],
    setupFiles: ["test/setup.ts"],
    // Reset every mock's calls and queued return values between tests, so a
    // module-level vi.fn() in one test cannot leak into the next.
    mockReset: true,
    restoreMocks: true,
  },
})
