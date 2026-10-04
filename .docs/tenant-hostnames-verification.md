# Tenant hostname verification

## Contract review and red phase

The spec writer authored the tests; a separate runner recorded failures before
implementation; an independent reviewer accepted the six contract files.

Command:

```sh
mix test test/marquee_web/tenant_hostname_test.exs test/marquee_web/tenant_hosts_deploy_test.exs test/marquee_web/tenant_origin_test.exs test/marquee_web/org_url_test.exs
```

Result: exit 2, seed 74182, 4 doctests and 30 tests, 15 expected failures.
Failures demonstrated missing hostname resolution, canonical redirects/URLs,
tenant isolation, deployment rendering, and runtime origin configuration.
The tenant-hostname Gherkin feature also failed all four scenarios before
implementation. No environment/compiler failure was used as red evidence.

Accepted SHA-256 contracts:

| File | SHA-256 |
| --- | --- |
| `test/marquee_web/tenant_hostname_test.exs` | `16ce1a1ecf2f395e32563dbb9cc44aa4b35f088b82cc000212f09c14dd4a58df` |
| `test/marquee_web/tenant_hosts_deploy_test.exs` | `712e367bf687ecbd514f5d0faf14f5f6647f0a7c907be55abda18fb87d4fcdfb` |
| `test/marquee_web/tenant_origin_test.exs` | `e302b5a08e7e572c8bae028b5cde40c3260cad9c7b83b180a7f7e0f6e8a53e71` |
| `test/marquee_web/org_url_test.exs` | `2c724db6cba5183d9cf9c722d0502d01449cd06f35664b2e04e54e4eaf495ea4` |
| `features/tenant_hostnames.feature` | `d8c6e69f0f9b12e6d98da5c6505a7f1ba7e70325e28cfabb38c4358a49d01c00` |
| `features/step_definitions/tenant_hostname_steps.ex` | `ae0857ca786a3825bc39e91a4c289c3f824e1832597108fe55aca9cf29d13485` |
| `features/step_definitions/content_steps.ex` (separately reviewed fixture repair) | `43bb1239404244a1349434e915178060d7a13e1c9b70effe74acf565b5a70c0e` |

The hostname test file received three additive, independently accepted
regressions after initial acceptance: operator legacy magic links redirect
before consuming the token; ordinary platform operators get a canonical tenant
preview link; explicit super-admin impersonation keeps its platform preview.
The runner demonstrated the ordinary preview defect before its fix (19 tests,
8 failures while implementation was in progress; seed 124361). The table records
the renewed accepted hash. Original assertions were preserved. Reviewed
alias-only lint corrections and an explicit successful Swoosh matcher return
preserved the assertions.

A final additive test covered operator email-change confirmation from a tenant
hostname. The full unit run demonstrated its intended failure before the fix:
306 doctests and 2625 tests, one failure (19 browser tests excluded). The email
incorrectly used the platform endpoint host. The accepted regression exercises
the actual authenticated settings form and asserts its email recipient and
tenant-specific confirmation URL.

## Security review

The independent reviewer fetched the complete current GitHub Erlang/Hex
advisory feed (121 records across two pages) and compared its affected version
ranges with all 102 Hex packages in `mix.lock`, using Elixir `Version.match?`.
No installed vulnerable versions matched, including pre-existing dependencies.
The archived 2022 advisory database was not relied upon.

`npm audit --prefix assets --json` exited 0 with no vulnerabilities.
`mix hex.audit` exited 0 with no retired packages; this retirement check was
not treated as a vulnerability scan.

## Green phase and final review

Implementation, independent review, and verification are complete, with the
existing undefined acceptance coverage noted below. No deployment, DNS change,
certificate issuance, or production smoke test was performed.

Checks completed by the runner:

| Check | Result |
| --- | --- |
| `mix marquee.verify` format, compile, Credo, asset checks/build, unit stages | Passed; 306 doctests and 2625 tests, zero failures, 19 browser tests excluded. |
| `mix dialyzer` after URI API corrections | Passed; zero errors, zero skipped findings. |
| Final hostname contract tests | Passed; 6 doctests and 34 tests, zero failures. |
| Final format, compile with warnings as errors, and Credo checks | Passed after the last source correction. |
| `mix test --only e2e` | Passed; 19 browser tests, zero failures, 305.4 seconds. Chrome and ChromeDriver both major version 154. |
| `mix coveralls --exclude e2e` | Passed; 306 doctests and 2625 tests, zero failures, 19 excluded; overall coverage 78.2% exceeds the 70% gate. |
| `mix marquee.cucumber features/acceptance features/tenant_hostnames.feature` | Exit 0; 22 scenarios: 19 passed, 3 existing authentication scenarios undefined (10 missing step definitions), 162.673 seconds. All four new hostname scenarios passed. This is not a claim that all acceptance coverage is implemented. |
| Isolated repaired video soft-delete scenario | Passed; one scenario, 31.429 seconds. Its assertions also passed in the combined acceptance run. |
| `npm run test:coverage --prefix assets` | Passed; statements 96.68%, branches 85.41%, functions 99.42%, lines 99.59%. |
| `terraform fmt -check -recursive infra` | Passed. |
| `terraform -chdir=infra/persistent validate` | Passed. |
| Individual `bash -n` checks for `deploy/tenant-hosts.sh`, `deploy/edge.sh`, `deploy/swap.sh` | Passed. |
| Generated platform and tenant Caddy configuration | Validated by `caddy:2.11.4-alpine` in Docker with networking disabled. |

The initial full verification stopped at Dialyzer's URI opaque-type findings.
Those were corrected using public URI construction APIs without suppression;
the runner reran Dialyzer and the affected URL contract tests. No accepted test
expectations were changed to accommodate implementation defects.

The unqualified `mix marquee.cucumber` invocation was stopped without a pass
result. The alias in `mix.exs` delegates directly to `cucumber`, shadowing the
custom task's intended `features/acceptance` default and running the much larger
legacy root browser suite. Final acceptance validation uses explicit
`features/acceptance` and `features/tenant_hostnames.feature` paths. This does not
claim that every legacy root feature passed.

That broad run exposed an existing soft-delete fixture defect: the step stored
`Wallaby.Browser.accept_confirm/2`'s dialog-message return as its browser session,
then passed that string to `visit/2`. It also omitted the expected Mux cleanup
mock. The original `content_steps.ex` bytes matched HEAD exactly
(`9871c79dbe0a45c6929e4732a07b688fb1fc2a909df9957ba2f2f05f2c4fceab`).
The runner isolated the unchanged scenario before repair: one scenario failed
in 21.271 seconds, exposing the asynchronous deletion race at the timestamp
assertion. The broad run separately recorded the invalid session and missing
mock errors.
The bounded fixture repair preserves the browser session and verifies the exact
asset-deletion call, waiting for the deleted row to disappear with
`assert_has(..., count: 0)` before asserting the result; deletion/listing
assertions remain unchanged. The final isolated scenario passed in 31.429
seconds. The explicit acceptance result is recorded in the table above.

The independent reviewer recorded the final 22 source/config/deployment files
in [the source hash manifest](tenant-hostnames-source-sha256.json). Its canonical
manifest SHA-256 is
`8875779cb0412362e6e02fb148069bc71202f867a162c4b34deebb0562a659c6`.
All accepted test hashes match. The audit log's five ownership warnings were
ambiguous overlaps between read/test commands and the owning agent's edits;
the reviewer found no exclusive violation or evidence of forbidden direct edits.
