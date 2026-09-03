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
    coverage: {
      // Istanbul instruments the source rather than reading V8's counters, so
      // branch and statement coverage line up with what esbuild actually
      // bundles from `js/`. Reports land in `assets/coverage/` (gitignored).
      provider: "istanbul",
      reporter: ["text", "html", "json"],
      reportsDirectory: "coverage",
      include: ["js/**/*.ts"],
      // `app.ts` is the esbuild entrypoint: it wires topbar, the LiveSocket,
      // and runtime-only imports (phoenix_html) that never resolve under the
      // test runner. Type-only declarations carry no executable lines, and the
      // mux_player shim is a thin re-export bundled straight by esbuild.
      exclude: ["js/app.ts", "js/types/**", "js/mux_player.js"],
      thresholds: {
        statements: 70,
        branches: 70,
        functions: 70,
        lines: 70,
      },
    },
  },
})
