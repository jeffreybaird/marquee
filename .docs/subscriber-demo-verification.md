# Subscriber demo verification

Verified locally on 2026-10-04 against The Workshop, using the checked-in
`priv/subscriber_demo/workshop_catalog.json` and real Mux streams.

## Final media

The 18 distinct Pexels woodworking clips were inspected using source thumbnails
and sampled video frames before ingestion. Mux reported every asset ready.
Thumbnails use the same playback IDs as the videos.

| Episode | Pexels ID | Mux duration |
| --- | --- | --- |
| Measure and mark | 6789574 | 34.36 seconds |
| Sand the surface | 6789575 | 35.28 seconds |
| Fill the grain | 6789582 | 30.52 seconds |
| Square the board | 20184480 | 31.11 seconds |
| Check the edge | 35222303 | 27.04 seconds |
| Across the table saw | 7493222 | 37.00 seconds |
| At the assembly bench | 7314256 | 23.88 seconds |
| Plane a clean face | 35170034 | 31.94 seconds |
| Polish the curve | 35323780 | 57.48 seconds |
| Drill at the workbench | 6789905 | 26.72 seconds |
| Shape the edge | 35323776 | 71.40 seconds |
| Brush away the dust | 6789566 | 29.48 seconds |
| Guide the cut | 7493219 | 33.28 seconds |
| Cut to length | 20660631 | 45.71 seconds |
| Smooth a round seat | 5759905 | 24.77 seconds |
| Follow the grain | 19655270 | 29.65 seconds |
| A steady sanding pass | 6789587 | 20.36 seconds |
| Shavings by hand | 6789898 | 26.64 seconds |

Each episode credits its creator on Pexels, with its source URL stored in the
manifest and displayed in the description. Imports used
`Marquee.Content.MuxClient.create_asset/2` with stable per-source idempotency keys.
No credentials are stored in the manifest.

## Browser evidence

Desktop used the default 1280-pixel browser viewport. Mobile verification used a
390 × 844 viewport in the same browser engine; this was responsive browser testing,
not a physical iOS or Android device test.

- Entered through **Try the subscriber demo** without registration, email, or payment.
- Opened **Inside The Workshop**, and verified the original three-episode playback journey before expanding the catalog to 18 episodes.
- Played actual footage for all three episodes, observing advancing player controls.
- Desktop saved **Sand the surface**, returned home, and resumed from the recorded
  `6.163867` second position. The player subsequently showed `0:18 / 0:35`.
- Mobile played **Measure and mark**, saved **Fill the grain** from Browse, returned
  home, and found **Measure and mark** with `0:16 remaining`. Reopening it supplied
  `18.228009` seconds as the resume position; the player advanced beyond that point.
- Both watchlists survived reload: desktop contained Sand the surface; mobile
  contained Fill the grain.
- Separate host cookie stores (`the-workshop.localhost` and `localhost`) supplied
  isolated visitors. A fresh mobile visitor had an empty watchlist and seeded
  Measure and mark progress, independent of desktop's updated Sand the surface
  history. Mobile writes did not alter desktop's watchlist or Continue Watching.
- The mobile homepage measured 390 pixels for both viewport and document width.
- Switching from a saved episode to an unsaved episode now refreshes the watchlist
  button correctly; the browser reproduction led to a regression test and fix.

Screenshots were saved in the task's persistent visualization directory as
`workshop-desktop-home.jpg`, `workshop-desktop-playback.jpg`,
`workshop-mobile-home.jpg`, `workshop-mobile-playback.jpg`, and
`workshop-mobile-third-episode.jpg`.

## Expanded browsing verification

After seeding the expanded manifest, the homepage rendered three distinct
collections with 12 cards each: Start here, Explore the process, and From the
workbench. Every row had substantial horizontal overflow within its scroll track
and could be scrolled independently. Mobile verification also exercised a
horizontal scroll gesture and confirmed a 390-pixel document within a 390-pixel
viewport. The series displayed 18 episodes, preserving the original three IDs.

The added Shape the edge episode played in the browser and its watchlist state
persisted on return. Desktop and mobile document widths matched their viewports
(1280 and 390 pixels), with carousel overflow contained within each row.

Cached playback exposed a metadata-listener race. Five regression cases now cover
already-loaded metadata, synchronous source changes, and stale pending seeks.
After the fix, mobile resumed Shape the edge from 38.943850 seconds and continued
past 56 seconds. A second mobile round trip resumed Polish the curve from
18.735572 seconds and advanced to 28.409678 seconds. Returning home showed
29 seconds remaining; desktop then resumed that position and displayed
`0:36 / 0:57`. Expanded screenshots are `workshop-expanded-desktop.jpg` and
`workshop-expanded-mobile.jpg` in the same visualization directory.

## Automated verification

The hero follow-up was reseeded locally with three slides: Inside The Workshop,
At the assembly bench, and Guide the cut. The removed text-only row stayed absent.
Desktop slide two opened episode seven and played to `0:06 / 0:23`; mobile slide
three opened episode thirteen and advanced beyond 11 seconds. The settled mobile
carousel fit the 390-pixel viewport. Evidence: `workshop-three-slide-mobile.jpg`.

The final implementation passed `mix marquee.verify`: 2,600 tests,
298 doctests, 157 JavaScript tests, and 19 browser E2E tests, plus formatting,
compilation, Credo, TypeScript, asset build, and Dialyzer. The two subscriber-demo
acceptance scenarios and the added three-slide scenario also passed. The entire broad Cucumber suite was not completed.
That partial run exposed a setup-nudge assertion synchronization failure. A
diagnostic confirmed persisted dismissal and eventual DOM absence; two assertions
were corrected to wait for that same expected absence, and the original scenario
then passed without changes to operator behavior or timeouts.

After final media support and the episode-switch fix, focused runs passed 42
subscriber-demo/Mux tests and 91 WatchLive tests, with formatting, compilation,
Credo, and Dialyzer clean. The mandatory test-first workflow recorded expected
failures, accepted test hashes, green results, and independent source review.
Session expiry, cleanup, tenant isolation, and write authorization are covered by
automated tests; browser verification covered live playback and navigation.

PR review follow-up removes tenant-slug checks from runtime eligibility, platform
entry, and cleanup discovery. Regression tests cover renamed and multiple demo
organizations, strict feature flags, deterministic entry selection, and bounded
cleanup after the flag is disabled. `Marquee.SubscriberDemo` is registered with
ExUnit's `doctest`; its three predicate examples include matching inputs and
both past and future expiration times, and all three execute successfully.

Repository-wide follow-up registers all 61 modules with application-authored
examples in `test/published_doctests_test.exs`. Its focused run passes 298 unique
doctests plus two coverage guards. Previous registrations were consolidated to
avoid duplicate execution. Repairs affect documentation and test setup, not
runtime behavior. The coverage guard excludes only dependency-generated examples
identified by compiler metadata, such as Ecto's inherited SQL examples on Repo;
future application-authored examples remain subject to registration checks.

The work has not been deployed. Production provisioning and the personal-site
entry URL are documented in `subscriber-demo.md`.
