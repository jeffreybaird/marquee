/**
 * Type declarations for the vendored Shepherd.js 15.3.0 (`shepherd.js`, ESM build).
 * The npm `shepherd.js` package is installed for its types only; esbuild never
 * bundles it. Its declarations export `Shepherd` by name, while the vendored
 * bundle exports the same object as `default`, so map it here.
 */
import { Shepherd } from "shepherd.js"

export * from "shepherd.js"
export default Shepherd
