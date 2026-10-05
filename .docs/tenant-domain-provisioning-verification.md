# Automatic tenant provisioning verification

The orchestrator delegated test authoring, authoritative execution, source
implementation, and independent review to separate native workflow roles.
Production deployment, DNS writes, and client enrollment are separate rollout
actions; this document records repository verification only.

## Accepted contracts and red evidence

| Contract | Initial red result | Accepted SHA-256 |
| --- | --- | --- |
| `test/marquee/tenant_domains_test.exs` | 12 tests failed on absent provisioning APIs; seed 4885. Additive current-configuration authorization regression reviewed separately. | `96bb5a3bf7676aaa595a2dac16ef8bffdda83baaee254b7eeac00d46b23daf4e` |
| `test/marquee/tenant_dnsimple_client_test.exs` | Adapter phase: 8 tests failed on absent DNS/probe APIs. | `8d17557f5809c73d6b616d69f2d97cc3c64cde25de749ca3e8013953ee8dbd64` |
| `test/marquee/tenant_readiness_probe_test.exs` | Same adapter red phase. | `a4b9ebf40ac57a6819f51c9a2f55cea5dbf15ca0f9a0891a696cb59730d5cb47` |
| `test/marquee_web/tenant_provisioning_routing_test.exs` | 8 tests failed before readiness routing was implemented; four additional query-mode authentication/navigation regressions failed before their fixes. | `c28db51307564751667cb029bfb5dbcf53ea22ca4965b55e667070728ba0abe8` |
| `test/marquee/tenant_domain_release_test.exs` | 2 tests failed on absent release plan/apply APIs. Additive malformed cutoff assertion reached `DateTime.from_iso8601(nil)` and failed before the guard. | `48f0016212a3ae970a7949f840a6d3af816df1aa19d06f64d408868a794c4d83` |
| `test/support/tenant_domain_clients.ex` | Reviewed scripted provider/probe fixtures, including additive resolver support. | `2ba9fb789b4158563f94c6287cb4486231e2b7c63be215ed7ee1f08ce1901e71` |
| `test/marquee_web/tenant_tls_deploy_test.exs` | 6 tests, 2 expected failures on absent positive render/apply paths. Negative guards require positive implementation to become meaningful. An additive default-pattern regression covers the remote workflow with unset or empty pattern. | `a35a803524e74b4c295e08ccc89c976dbb9be7444d78e70320d01f1bc7d290cd` |
| `test/marquee_web/tenant_provisioning_runtime_test.exs` | Runtime/schema phase: 5 tests, 2 expected runtime configuration failures. | `90e54f47508e839847ef31a75ca9c532c305a1a4c8d53cef78c6510a0eb3ab33` |
| `test/marquee/tenant_domain_schema_test.exs` | Schema constraints passed after the migration; reviewed independently. | `d7977c89eaa35d9d2143eb3aebd99dd3f016c5099001d231affba9ef0da7c79a` |
| `features/tenant_provisioning.feature` | 2 scenarios failed before enrollment/routing implementation. | `9ecf8a3b74cc21c147cae31652df1ffc138956058efa6997fa33b7b03f4f86fe` |
| `features/step_definitions/tenant_provisioning_steps.ex` | Same Gherkin red phase. | `21cf4d8fc95e1105163e594f313123efe3aaa3a674d5d7581554a537948b5e81` |

The initial failures were missing expected implementation APIs, not unavailable
infrastructure. Later integrated runs must exercise the full downstream routing
and adapter assertions after the core APIs exist. Accepted assertions cannot be
weakened to accommodate implementation errors.

## Security advisory review

The independent reviewer refreshed all 121 current GitHub Erlang/Hex advisory
records and compared their affected ranges with the 102 locked Hex packages:
zero affected installed versions. `npm audit` reported zero vulnerabilities.
The reviewer also checked all 17 current Caddy repository advisories. The existing
Caddy 2.11.4 pin was affected by [GHSA-6365-7ppr-5r92](https://github.com/caddyserver/caddy/security/advisories/GHSA-6365-7ppr-5r92),
a wrong-upstream/authentication bypass race involving `forward_auth` and
`reverse_proxy`. This site's configuration does not use `forward_auth`; other
shared sites cannot be assumed safe. The compatible image pin was upgraded to
2.11.6-alpine for final edge verification (the advisory is fixed starting at
2.11.5, but that Docker image tag was unavailable). Other published Caddy
advisories were fixed at or before 2.11.4.

## Independent review

The reviewer accepted all 11 final test/fixture/feature hashes in
[the test manifest](tenant-domain-provisioning-tests-sha256.json) and reviewed
32 source/configuration files recorded in
[the source manifest](tenant-domain-provisioning-source-sha256.json). The source
manifest SHA-256 is `9bfb60f4a14334fb437a3d67bac0c8c48d7aa6fc27189a4be9c383efe4429564`.

The audit review examined 45 new entries. Fifteen entries carried ownership
flags with ambiguous concurrent tool attribution; their commands were read-only
or role-owned formatting/file writes, and accepted tests retained their hashes.
No independent source/test ownership violation was found.

## Final results

The runner completed the full read-only verification pipeline after source and
test owners formatted their files. Formatting, warnings-as-errors compilation,
strict Credo, asset type checks/tests/build, 307 doctests and 2,671 tests, Dialyzer,
and all 19 browser tests passed. Browser execution took 307 seconds. Application
coverage passed at 78.4% with 307 doctests and 2,672 tests (including the final
added edge regression); asset coverage also passed. A subsequent targeted run
passed both release tests and all seven edge tests.

Fresh-process release testing first exposed missing Oban/PubSub startup
dependencies that normal application-started tests could not reveal. The fixes
were independently reviewed. A subsequent nonempty plan/apply check passed:
snapshot/status used only database services; apply persisted one pending job and
an audit record without starting the endpoint, application supervisor, or worker
queues. A fresh-process retry retained exactly one pending job, proving
idempotence, and the temporary Oban instance stopped afterward. Temporary
verification records, jobs, and audit records were removed afterward.

Real Caddy 2.11.6 validation found and corrected an unsupported matcher and a
shell default-pattern escaping error. The final generated production
configuration validates. Runtime checks use a local test CA rather than issuing
public certificates: managed hosts proxy correctly, unrelated static sites take
precedence, foreign hosts return 404, and the private ask relay supplies the
expected path and HTTPS scheme. A permitted TLS handshake succeeds and a denied
one fails, with the denied permission request captured as HTTP 403. Stopping
the blue backend successfully routed permission traffic through green. No live
DNS records or production certificates were created.

A Linux container also executed the real helper with Caddy 2.11.6: staged
candidate validation and reload passed, the bound Caddyfile inode and unrelated
static files were preserved, and an injected reload failure restored all four
previous files before a successful rollback reload. Two concurrent applies
completed under the real `/usr/bin/flock`. A Docker Compose invocation shim
routed calls to the real Caddy binary in the isolated container; only the first
reload failure was injected deliberately.

The intended acceptance command used explicit `features/acceptance`,
`features/tenant_hostnames.feature`, and `features/tenant_provisioning.feature`.
It exited 0 after 164.893 seconds: 24 scenarios, 21 passed and three pre-existing
undefined authentication scenarios. Both new provisioning scenarios passed.
This is not a claim that all acceptance pathways are implemented. The
unqualified `marquee.cucumber` alias shadows its narrower custom task and was
not used; the broader legacy browser feature tree was not part of this run.

All required checks and the additional deployment/release verification are
complete. Production migration remains a separate operation requiring the
reviewed client selection and rollout configuration.
