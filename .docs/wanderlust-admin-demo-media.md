# Wanderlust admin demo media

The `wanderlust-v2` template contains 60 distinct travel shorts: 48 initially seeded clips and 12 additional clips available through Add sample clip. Each of the four collections starts with 12 clips and has three extras. The original 18 clips retain their slugs, playback IDs, and initial flags. New and reset sessions receive the expanded catalog; existing sessions keep their edits until reset. These are short location, landscape, and food scenes, not narrated destination guides or full-length television episodes. Titles and descriptions describe the observed footage.

## Source and license

Footage was selected through the Pexels API and visually reviewed on October 4–5, 2026 (America/New_York). The [Pexels license](https://www.pexels.com/license/) permits use in websites and applications. This free product demonstration does not sell footage, offer a stock-footage download library, or imply creator endorsement. The [API guidelines](https://www.pexels.com/api/documentation/) request a prominent Pexels link and creator attribution; preserve both in the demo and the per-clip source metadata.

## Media lifecycle

Imported once through `Marquee.Content.MuxClient.create_asset/2`, with stable `wanderlust-admin-demo:v1:pexels:<source-id>` idempotency keys for the original clips and `wanderlust-admin-demo:v2:pexels:<source-id>` for the 42 additions and basic video quality. Mux supplies the actual durations and public playback IDs recorded in `priv/admin_demo/wanderlust_catalog.json`. Sandbox metadata may be edited or removed, but shared assets must never be deleted by sandbox actions, reset, expiry, or cleanup. Sandbox video records must not own the underlying Mux asset IDs.

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
| Crossing the Bosphorus | City journeys | 32.03 | Yes | [Yaşar Başkurt](https://www.pexels.com/video/passenger-ferry-crossing-bosphorus-strait-39918920/) |
| Istanbul After Dark | City journeys | 41.08 | Yes | [İsmail Ünlü](https://www.pexels.com/video/nighttime-metro-train-on-istanbul-bridge-39896796/) |
| Bosphorus at Sunset | City journeys | 16.98 | Yes | [Sururi Ballıdağ Director](https://www.pexels.com/video/istanbul-s-bosphorus-at-sunset-with-boats-35345603/) |
| Prague Old Town | City journeys | 13.35 | Yes | [Samuel Burai](https://www.pexels.com/video/old-town-square-prague-20640019/) |
| The Astronomical Clock | City journeys | 14.15 | Yes | [Samuel Burai](https://www.pexels.com/video/astronomical-clock-tower-20640178/) |
| Singapore Reflections | City journeys | 20.23 | Yes | [Timo Volz](https://www.pexels.com/video/singapore-city-skyline-at-night-reflections-30570498/) |
| Marina Bay Skyline | City journeys | 8.73 | Yes | [CK Seng](https://www.pexels.com/video/singapore-skyline-with-marina-bay-sands-32444379/) |
| Along the Paris Boulevards | City journeys | 36.27 | Yes | [Artem Danevych](https://www.pexels.com/video/a-moving-cars-on-the-road-between-city-buildings-in-paris-14886910/) |
| Clouds over Paris | City journeys | 55.90 | No | [Alin Buda](https://www.pexels.com/video/clouds-over-paris-12329723/) |
| Above the Amalfi Coast | Coastal escapes | 27.06 | Yes | [Marco Benci](https://www.pexels.com/video/stunning-aerial-view-of-coastal-agerola-29292844/) |
| Hillside Positano | Coastal escapes | 18.69 | Yes | [K](https://www.pexels.com/video/a-view-of-the-town-of-positano-italy-20156101/) |
| Atrani by the Sea | Coastal escapes | 15.89 | Yes | [K](https://www.pexels.com/video/drone-footage-of-atrani-city-on-the-amalfi-coast-italy-15437344/) |
| An Island Retreat | Coastal escapes | 23.08 | Yes | [Videographer Shiyaz](https://www.pexels.com/video/aerial-footage-of-a-beach-resort-4010511/) |
| Maldives Shoreline | Coastal escapes | 12.28 | Yes | [Hussain Naushad](https://www.pexels.com/video/tropical-beach-paradise-in-maldives-35215090/) |
| Heron on the Beach | Coastal escapes | 26.20 | Yes | [Abdulla Nadeem](https://www.pexels.com/video/serene-heron-on-tropical-paradise-beach-30330894/) |
| Mykonos at Sunset | Coastal escapes | 7.67 | Yes | [Aaron Hairston](https://www.pexels.com/video/mykonos-sunset-27374533/) |
| A Bay in Rhodes | Coastal escapes | 22.51 | Yes | [David Pickup |  Advertising & Marketing  🇬🇧](https://www.pexels.com/video/aerial-view-of-st-paul-s-bay-in-rhodes-greece-34364061/) |
| Skopelos from Above | Coastal escapes | 23.56 | Yes | [Lazar Krstić](https://www.pexels.com/video/drone-view-over-the-main-town-of-skopelos-island-greece-13208744/) |
| Australian Coastlines | Coastal escapes | 10.59 | Yes | [Harrison Reilly](https://www.pexels.com/video/aerial-view-of-stunning-australian-coastline-34783356/) |
| Cape Leeuwin Lighthouse | Coastal escapes | 17.72 | No | [Sergey Guk](https://www.pexels.com/video/majestic-cape-leeuwin-lighthouse-and-rugged-coast-31256139/) |
| Waves against the Rocks | Coastal escapes | 13.33 | No | [Harrison Reilly](https://www.pexels.com/video/aerial-view-of-a-rocky-coastline-with-waves-crashing-on-it-27300952/) |
| At the Night Market | Food & culture | 6.04 | Yes | [LayG Traveller](https://www.pexels.com/video/bustling-thai-night-market-food-stall-29162655/) |
| Street-Side Donuts | Food & culture | 6.01 | Yes | [My Walking Diary](https://www.pexels.com/video/food-vendors-selling-donuts-on-the-street-5700598/) |
| A Thai Food Stall | Food & culture | 12.44 | Yes | [LayG Traveller](https://www.pexels.com/video/vibrant-thai-night-market-food-stall-29162582/) |
| Night Market Flavors | Food & culture | 12.92 | Yes | [LayG Traveller](https://www.pexels.com/video/vibrant-thai-street-food-market-at-night-29936628/) |
| In the Pasta Kitchen | Food & culture | 85.56 | Yes | [cottonbro studio](https://www.pexels.com/video/pasta-kitchen-cooking-indoors-4252802/) |
| Spaghetti in Motion | Food & culture | 18.08 | Yes | [Miguel Á. Padriñán](https://www.pexels.com/video/spaghetti-pasta-1793155/) |
| Pasta from the Pot | Food & culture | 24.04 | Yes | [Antonius Ferret](https://www.pexels.com/video/person-straining-pasta-6222558/) |
| Rolling Fresh Pasta | Food & culture | 44.12 | Yes | [cottonbro studio](https://www.pexels.com/video/a-person-is-using-a-pasta-machine-to-make-pasta-4252810/) |
| The Matcha Ritual | Food & culture | 11.72 | Yes | [Ivan S](https://www.pexels.com/video/a-person-mixing-matcha-on-a-table-8507721/) |
| Time for Tea | Food & culture | 31.60 | Yes | [cottonbro studio](https://www.pexels.com/video/a-woman-pouring-tea-into-cup-8748746/) |
| Whisking the Bowl | Food & culture | 17.24 | No | [Ivan S](https://www.pexels.com/video/a-person-whisking-the-tea-on-the-bowl-8507724/) |
| Textiles of the Medina | Food & culture | 16.46 | No | [Taryn Elliott](https://www.pexels.com/video/slow-motion-footage-of-a-man-walking-down-the-steps-of-an-alley-looking-at-carpets-of-assorted-designs-hanging-on-walls-3015533/) |
| Godafoss in Winter | Wild horizons | 18.52 | Yes | [Sergey Guk](https://www.pexels.com/video/breathtaking-aerial-view-of-godafoss-in-winter-29499247/) |
| Icelandic Cascades | Wild horizons | 26.59 | Yes | [Gylfi Gylfason](https://www.pexels.com/video/breathtaking-icelandic-waterfall-cascades-39451771/) |
| Waterfall at Sunset | Wild horizons | 20.09 | Yes | [Gylfi Gylfason](https://www.pexels.com/video/majestic-icelandic-waterfall-mist-at-sunset-30227457/) |
| Peaks of Patagonia | Wild horizons | 17.15 | Yes | [Florian Delée](https://www.pexels.com/video/majestic-snow-capped-mountains-in-patagonia-30240553/) |
| The Patagonian Andes | Wild horizons | 20.54 | Yes | [Sergey Guk](https://www.pexels.com/video/majestic-glacial-views-of-patagonian-andes-32987049/) |
| Elephants on the Move | Wild horizons | 25.09 | Yes | [ROMAN ODINTSOV](https://www.pexels.com/video/african-elephants-walking-in-a-grass-field-11760783/) |
| Life on the Savanna | Wild horizons | 31.80 | Yes | [Magda Ehlers](https://www.pexels.com/video/zebras-and-wildebeests-in-african-savanna-32416221/) |
| Misty Norwegian Fjord | Wild horizons | 7.67 | Yes | [Dominik Gryzbon](https://www.pexels.com/video/serene-norwegian-fjord-with-misty-mountains-30443160/) |
| Between Fjord and Mountain | Wild horizons | 15.96 | No | [Dominik Gryzbon](https://www.pexels.com/video/scenic-view-of-norwegian-fjord-landscape-30443114/) |

## Verification

All 60 assets reported ready from Mux. Source thumbnails for the 42 additions were visually reviewed. All 60 public HLS streams decoded successfully for two seconds, and all 60 Mux thumbnails returned successfully. Decoded frames from the 42 additions were visually reviewed. Evidence: `/tmp/wanderlust-expanded-verification/results.json`, `review-{0,1,2}.jpg`, and `/tmp/wanderlust-expanded-playback.log`. Total duration is 1,229 seconds (about 20.5 minutes).
