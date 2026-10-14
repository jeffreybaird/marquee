# Third-party notices

Third-party components retain their upstream licenses. This notice records the
Shepherd distribution; it does not replace notices shipped with other dependencies.
Marquee's AGPL-3.0-only license applies to its original project code.

## Driver.js 1.9.0

Used under the MIT license. The complete upstream license is preserved in
[assets/vendor/driver.LICENSE.txt](assets/vendor/driver.LICENSE.txt).

The vendored JavaScript is the unmodified npm distribution's `dist/driver.js.mjs`,
with the MIT license prepended as a `/*! ... */` legal-comment banner so it
survives minification. The combined file is stored as `assets/vendor/driver.js`.

The vendored CSS (`dist/driver.css` -> `assets/vendor/driver.css`) and
TypeScript declarations (`dist/driver.js.d.ts` -> `assets/vendor/driver.d.ts`)
are unchanged from the published archive.

Package source: https://www.npmjs.com/package/driver.js/v/1.9.0. The package
declares no runtime dependencies in its `package.json`.

## Shepherd.js 15.3.0

Used under GNU AGPL version 3. The complete upstream license, including its
copyright and warranty terms, is preserved in
[assets/vendor/shepherd.LICENSE.md](assets/vendor/shepherd.LICENSE.md).

The vendored JavaScript is the unmodified npm distribution's
`dist/js/shepherd.mjs`, stored as `assets/vendor/shepherd.js`. Its matching
source map, including the embedded original source, is stored beside it as
`shepherd.mjs.map`. Package source: https://www.npmjs.com/package/shepherd.js/v/15.3.0.

The source map identifies these bundled dependencies:

- deepmerge-ts 8.0.1: BSD-3-Clause.
- @floating-ui/dom 1.8.0: MIT.
- @floating-ui/core 1.8.0: MIT.
- @floating-ui/utils 0.2.12: MIT.

Their complete notices are preserved in
[assets/vendor/shepherd-dependencies.LICENSE.txt](assets/vendor/shepherd-dependencies.LICENSE.txt).
The npm tooling dependency graph can resolve newer compatible versions; the
versions above identify the code inside the published vendored runtime.

## bcrypt_elixir 3.3.2: unresolved upstream notice discrepancy

Its `c_src/blowfish.c` and `c_src/blf.h` carry three-clause BSD terms, while
its package `LICENSE` and package metadata retain four-clause BSD terms.
The upstream notices are preserved unchanged. This discrepancy remains unresolved;
this notice does not assert that the entire dependency graph has received a
complete license-compatibility review.
