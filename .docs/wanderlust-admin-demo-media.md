# Wanderlust admin demo media

The `wanderlust-v1` template contains 18 distinct travel shorts: 12 initially seeded clips and six clips available through Add sample clip. These are short location, landscape, and food scenes, not narrated destination guides or full-length television episodes. Titles and descriptions describe the observed footage.

## Source and license

Footage was selected through the Pexels API and visually reviewed on October 4, 2026 (America/New_York). The [Pexels license](https://www.pexels.com/license/) permits use in websites and applications. This free product demonstration does not sell footage, offer a stock-footage download library, or imply creator endorsement. The [API guidelines](https://www.pexels.com/api/documentation/) request a prominent Pexels link and creator attribution; preserve both in the demo and the per-clip source metadata.

## Media lifecycle

Imported once through `Marquee.Content.MuxClient.create_asset/2`, with stable `wanderlust-admin-demo:v1:pexels:<source-id>` idempotency keys and basic video quality. Mux supplies the actual durations and public playback IDs recorded in `priv/admin_demo/wanderlust_catalog.json`. Sandbox metadata may be edited or removed, but shared assets must never be deleted by sandbox actions, reset, expiry, or cleanup. Sandbox video records must not own the underlying Mux asset IDs.

## Catalog

| Clip | Collection | Seconds | Initial | Creator / source |
| --- | --- | ---: | --- | --- |
| Venice by Gondola | City journeys | 10.84 | Yes | [K](https://www.pexels.com/video/a-gondola-is-traveling-down-a-narrow-canal-28552996/) |
| Along the Grand Canal | City journeys | 15.71 | Yes | [Dominik Gryzbon](https://www.pexels.com/video/scenic-view-of-venice-grand-canal-36328559/) |
| Palaces on the Water | City journeys | 37.20 | No | [Magda Ehlers](https://www.pexels.com/video/explore-venice-s-historic-grand-canal-architecture-29913630/) |
| A Sea of Green | Wild horizons | 32.92 | Yes | [Tom Fisk](https://www.pexels.com/video/aerial-view-of-lush-green-rice-paddies-35902964/) |
| Bali from Above | Wild horizons | 18.54 | Yes | [Florian Delée](https://www.pexels.com/video/scenic-aerial-view-of-balinese-rice-terraces-36492278/) |
| The Shape of the Harvest | Wild horizons | 35.91 | No | [Michele Esposito](https://www.pexels.com/video/drone-shot-of-a-rice-farming-in-multi-layer-terraces-4232189/) |
| Turning Takoyaki | Food & culture | 8.73 | Yes | [thebaddkid](https://www.pexels.com/video/making-takoyaki-a-japanese-street-food-35927188/) |
| A Taste of Toyosu | Food & culture | 7.67 | Yes | [Tatsuo Nakamura](https://www.pexels.com/video/vibrant-street-food-stall-in-toyosu-market-34294418/) |
| Walking Asakusa | Food & culture | 10.70 | No | [Tatsuo Nakamura](https://www.pexels.com/video/lively-asakusa-street-market-experience-34183487/) |
| Above the Clouds | Wild horizons | 21.25 | Yes | [Yaroslav Shuraev](https://www.pexels.com/video/an-aerial-footage-of-people-hiking-4763911/) |
| On the Alpine Trail | Wild horizons | 12.85 | Yes | [Alexander Buzurnyuk](https://www.pexels.com/video/hiker-with-trekking-poles-walking-high-in-snowy-mountains-almaty-kazakhstan-26508101/) |
| The Summit Moment | Wild horizons | 16.96 | No | [Taryn Elliott](https://www.pexels.com/video/a-man-standing-on-rocks-feeling-excited-7815657/) |
| Lagos from the Air | Coastal escapes | 10.74 | Yes | [A.S. Kacar](https://www.pexels.com/video/lagos-portugal-27535847/) |
| Light on the Atlantic | Coastal escapes | 11.51 | Yes | [Lazar Krstić](https://www.pexels.com/video/sunlight-over-lughthouse-near-porto-10825879/) |
| Where Land Meets Sea | Coastal escapes | 17.35 | No | [Carola  Bischof](https://www.pexels.com/video/portugal-20615442/) |
| Through the Artisan Market | City journeys | 8.17 | Yes | [Arvydas Laukutis](https://www.pexels.com/video/bustling-day-at-moroccan-artisan-market-30055420/) |
| Colors of Chefchaouen | City journeys | 16.37 | Yes | [Earth Photart](https://www.pexels.com/video/vibrant-streets-of-chefchaouen-morocco-34499566/) |
| A Morning in the Medina | City journeys | 8.88 | No | [Abdelmoughit  LAHBABI](https://www.pexels.com/video/charming-moroccan-market-street-scene-32719990/) |

## Verification

Every asset reported ready from Mux. Initial visual review used source thumbnails. Final media verification successfully decoded the first two seconds of all 18 public HLS streams and retrieved all 18 matching Mux thumbnails; a contact sheet of decoded frames was visually reviewed. Browser verification of the delivered demo remains a release gate.
