import { createHash } from "node:crypto"
import { readFileSync } from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

import { describe, expect, it } from "vitest"

/**
 * Accepted-test contract for PR 01 of the Shepherd -> Driver.js migration.
 *
 * This PR vendors driver.js 1.9.0 under assets/vendor/ so the repository can
 * resolve the import, build and test against it, while leaving every existing
 * Shepherd tour untouched. The following assertions pin:
 *
 *   - that the vendored module resolves and exports `driver`
 *   - that the full MIT license appears as a legal-comment banner at the top
 *     of the bundle (so esbuild preserves it through minification)
 *   - that the sibling CSS, type declarations and standalone LICENSE match the
 *     bytes published to npm (sha256)
 *   - that assets/package.json pins driver.js at exactly 1.9.0
 *   - that Shepherd stays vendored and present
 *   - that THIRD_PARTY_NOTICES.md advertises both Shepherd.js and Driver.js
 */

// SHA-256 digests of the exact bytes published in the driver.js 1.9.0 npm
// tarball. Any drift from the upstream payload must be caught here; a
// re-vendor needs explicit review, not a silently-updated digest.
const DRIVER_CSS_SHA256 =
  "d095d440021fcf133ad46d37f18a2745fb76440f14f5208d17e203c039f765c9"
const DRIVER_DTS_SHA256 =
  "80f1a344ab116d3fd6efb22ae11ab81f5f3378f536742bef5596553d8b7a6197"
const DRIVER_LICENSE_SHA256 =
  "ec3ce3a08736fefd6a03a6d5b52b0705e6919fe06de9d7bd3fb63dcfb492d76d"

const here = path.dirname(fileURLToPath(import.meta.url))

const repoFile = (relFromAssets: string): string =>
  path.resolve(here, "..", "..", relFromAssets)

const repoRoot = (relFromRepo: string): string =>
  path.resolve(here, "..", "..", "..", relFromRepo)

const sha256 = (bytes: Buffer): string =>
  createHash("sha256").update(bytes).digest("hex")

describe("driver.js vendored distribution", () => {
  it("exports a driver function from the vendored module", async () => {
    const mod = await import("../../vendor/driver.js")

    expect(typeof mod.driver).toBe("function")
  })

  it("carries the full MIT license as a leading legal-comment banner", () => {
    const source = readFileSync(repoFile("vendor/driver.js"), "utf8")
    const head = source.split("\n").slice(0, 30).join("\n")

    for (const needle of [
      "/*!",
      "driver.js 1.9.0",
      "The MIT License",
      "Copyright (c) Kamran Ahmed",
      "Permission is hereby granted, free of charge",
      "WITHOUT WARRANTY OF ANY KIND",
      "*/",
    ]) {
      expect(head).toContain(needle)
    }

    const bannerStart = source.indexOf("/*!")
    const bannerEnd = source.indexOf("*/", bannerStart)
    expect(bannerStart).toBeGreaterThanOrEqual(0)
    expect(bannerEnd).toBeGreaterThan(bannerStart)

    const lineOfBannerEnd = source.slice(0, bannerEnd).split("\n").length
    expect(lineOfBannerEnd).toBeLessThan(30)
  })

  it("vendors driver.css with the exact bytes published to npm", () => {
    const bytes = readFileSync(repoFile("vendor/driver.css"))

    expect(sha256(bytes)).toBe(DRIVER_CSS_SHA256)
  })

  it("vendors driver.d.ts with the exact bytes published to npm", () => {
    const bytes = readFileSync(repoFile("vendor/driver.d.ts"))

    expect(sha256(bytes)).toBe(DRIVER_DTS_SHA256)
  })

  it("vendors driver.LICENSE.txt with the exact bytes published to npm", () => {
    const bytes = readFileSync(repoFile("vendor/driver.LICENSE.txt"))

    expect(sha256(bytes)).toBe(DRIVER_LICENSE_SHA256)
  })

  it("ships the standalone LICENSE file with the full MIT license text", () => {
    const text = readFileSync(repoFile("vendor/driver.LICENSE.txt"), "utf8")

    for (const needle of [
      "The MIT License",
      "Copyright (c) Kamran Ahmed",
      "Permission is hereby granted, free of charge",
      "WITHOUT WARRANTY OF ANY KIND",
    ]) {
      expect(text).toContain(needle)
    }
  })

  it("pins driver.js to exactly 1.9.0 in assets/package.json devDependencies", () => {
    const pkg = JSON.parse(readFileSync(repoFile("package.json"), "utf8"))

    expect(pkg.devDependencies["driver.js"]).toBe("1.9.0")
  })

  it("leaves Shepherd vendored and listed in assets/package.json", () => {
    const shepherd = readFileSync(repoFile("vendor/shepherd.js"))
    expect(shepherd.byteLength).toBeGreaterThan(0)

    const pkg = JSON.parse(readFileSync(repoFile("package.json"), "utf8"))
    expect(pkg.devDependencies["shepherd.js"]).toBeDefined()
  })

  it("advertises both Shepherd.js and Driver.js 1.9.0 in THIRD_PARTY_NOTICES.md", () => {
    const notices = readFileSync(repoRoot("THIRD_PARTY_NOTICES.md"), "utf8")

    expect(notices).toMatch(/Shepherd\.js/)
    expect(notices).toMatch(/Driver\.js/)
    expect(notices).toContain("1.9.0")
    expect(notices).toContain("assets/vendor/driver.LICENSE.txt")
  })
})
