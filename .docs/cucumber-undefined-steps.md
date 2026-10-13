# Cucumber: undefined steps report and proposal

Generated for [issue #28](https://github.com/jeffreybaird/marquee/issues/28), task 2.
Baseline on `main` (full `features/**` run, Wallaby): 303 scenarios, 94 passed,
31 failed, 178 undefined.

## Proposal (decision needed)

1. **Delete `features/acceptance/authentication.feature`.** It is an older
   duplicate of `features/authentication.feature` (same flows, different step
   wording, 11 undefined steps). Test deletion requires explicit approval.
2. **Tag every scenario that still has undefined steps with `@wip`** and run the
   gated suite with `--tags "not @wip"` in `mix precommit` and CI, so the suite
   is strict and green while step definitions are written incrementally. The
   36 files below all describe real product areas (contexts exist for billing,
   catalog, live events, webhooks, viewer flows), so removal would lose intent.
3. **Write step definitions domain by domain**, starting with the smallest gaps
   (`super_admin_org_management` 1, `admin_dashboard` 3, `tags_management` 3,
   `audit_logging__organization_audit_log` 4), removing `@wip` as each file goes
   green. Scenarios for flows the product does not have (verify per file before
   writing steps) should be removed, not stubbed.

Alternative to 2: move undefined feature files to `features/wip/` and run only
`features/*.feature` + `features/acceptance`. Same effect, no tag edits, but
loses the per-scenario granularity.

## Report


Generated statically by matching every pickle step against the step registry (same matcher `mix cucumber` uses).

37 feature files, 180 scenarios, 606 undefined step occurrences.

| Feature | Scenarios with undefined steps | Undefined step occurrences |
|---|---:|---:|
| `features/acceptance/authentication.feature` | 3 | 11 |
| `features/admin_dashboard__admin_dashboard.feature` | 1 | 3 |
| `features/admin_dashboard__landing_page_builder.feature` | 9 | 24 |
| `features/admin_dashboard__organization_settings.feature` | 2 | 7 |
| `features/admin_dashboard__super_admin_dashboard.feature` | 1 | 3 |
| `features/analytics__operator_organization_analytics.feature` | 4 | 12 |
| `features/analytics__super_admin_platform_analytics.feature` | 3 | 6 |
| `features/audit_logging__organization_audit_log.feature` | 2 | 4 |
| `features/audit_logging__super_admin_platform_audit_log.feature` | 3 | 8 |
| `features/billing__coupon_management.feature` | 5 | 13 |
| `features/billing__stripe_connect_onboarding.feature` | 3 | 13 |
| `features/billing__subscription_plan_management.feature` | 5 | 15 |
| `features/billing__viewer_subscription_flow.feature` | 7 | 37 |
| `features/branding__organization_branding_configuration.feature` | 2 | 6 |
| `features/branding__theme_and_color_customization.feature` | 8 | 26 |
| `features/catalog__hero_banner_management.feature` | 10 | 29 |
| `features/catalog__homepage_row_management.feature` | 6 | 18 |
| `features/catalog__layout_presets.feature` | 2 | 6 |
| `features/catalog__row_card_display_options.feature` | 5 | 15 |
| `features/content_consumption__content_discovery_and_browsing.feature` | 5 | 21 |
| `features/content_consumption__queue_management.feature` | 8 | 33 |
| `features/content_consumption__video_playback.feature` | 9 | 41 |
| `features/content_consumption__watch_history.feature` | 3 | 12 |
| `features/content_consumption__watchlist_and_favorites.feature` | 5 | 20 |
| `features/content_management__collections_management.feature` | 7 | 20 |
| `features/content_management__series_and_season_management.feature` | 6 | 17 |
| `features/content_management__tags_management.feature` | 1 | 3 |
| `features/content_management__video_upload_and_management.feature` | 13 | 39 |
| `features/live_events__live_event_calendar_export.feature` | 8 | 26 |
| `features/live_events__live_event_google_calendar_link.feature` | 2 | 7 |
| `features/live_events__live_event_listing_viewer.feature` | 7 | 23 |
| `features/super_admin_org_management.feature` | 1 | 1 |
| `features/team_membership_management.feature` | 5 | 16 |
| `features/viewer_management__operator_viewer_impersonation.feature` | 2 | 8 |
| `features/viewer_management__viewer_account_management.feature` | 4 | 13 |
| `features/viewer_management__viewer_registration_and_login.feature` | 6 | 28 |
| `features/webhooks__stripe_webhook_processing.feature` | 7 | 22 |


## `features/acceptance/authentication.feature`

- **Operator registers with a new organization**
  - `I submit the registration form with a valid email, password, and organization name`
  - `an operator account is created`
  - `a new organization is created with an auto-generated slug`
  - `a confirmation email is sent to my address`
  - `I am redirected to the admin dashboard`
- **Operator logs in with valid credentials**
  - `I submit valid credentials at the login page`
  - `a session token is created`
  - `I am redirected to the admin dashboard`
- **Operator fails login with wrong password**
  - `I submit an incorrect password`
  - `I see an invalid credentials error`
  - `no session is created`

## `features/admin_dashboard__admin_dashboard.feature`

- **Dashboard stats reflect current organization data**
  - `my organization has subscribers, videos, and revenue`
  - `I view the dashboard`
  - `the displayed stats match the current organization data`

## `features/admin_dashboard__landing_page_builder.feature`

- **Operator adds a feature section**
  - `I add a section of type feature`
  - `a feature section appears in the landing page`
- **Operator adds a testimonial section**
  - `I add a section of type testimonial`
  - `a testimonial section appears in the landing page`
- **Operator adds a CTA section**
  - `I add a section of type CTA`
  - `a CTA section appears in the landing page`
- **Operator edits a landing page section**
  - `I edit its content and save`
  - `the updated content is published to the landing page`
- **Operator adds a FAQ item**
  - `a FAQ section exists`
  - `I add a question and answer pair`
  - `the FAQ item appears within the FAQ section`
- **Operator removes a FAQ item**
  - `a FAQ section has items`
  - `I remove a FAQ item`
  - `it is removed from the FAQ section`
- **Operator reorders landing page sections**
  - `the landing page has multiple sections`
  - `I move a section up or down`
  - `the display order updates accordingly`
- **Operator links an existing video to a landing page section**
  - `a video section exists and videos are available`
  - `I open the video picker and select an existing video`
  - `the video is linked to that landing page section`
- **Operator uploads a new video for a landing page section**
  - `a video section exists`
  - `I upload a new video file via the video picker`
  - `the video is uploaded to Mux`
  - `linked to that landing page section`

## `features/admin_dashboard__organization_settings.feature`

- **Owner views Stripe Connect status**
  - `I am on the organization settings page`
  - `I view the settings page`
  - `I see whether Stripe Connect is connected or pending`
- **Owner initiates Stripe Connect onboarding**
  - `I am on the organization settings page`
  - `Stripe Connect is not yet connected`
  - `I click to connect my Stripe account`
  - `I am redirected to the Stripe OAuth flow`

## `features/admin_dashboard__super_admin_dashboard.feature`

- **Super admin views the platform dashboard**
  - `I navigate to /super/`
  - `I see platform-level stats`
  - `I see links to organizations, users, analytics, and the audit log`

## `features/analytics__operator_organization_analytics.feature`

- **Operator views content performance table**
  - `watch count, completion rate, and average watch time`
- **Operator views individual video analytics**
  - `a video exists with watch data`
  - `I navigate to /admin/analytics/videos/:video_id`
  - `I see watch stats, completion rate, average watch time,`
  - `a drop-off distribution showing where viewers stop watching`
- **Operator views series analytics**
  - `a series exists with watch data`
  - `I navigate to /admin/analytics/series/:series_id`
  - `I see per-season stats, episode completion rates, and funnel data`
  - `next-season transition rates showing how many viewers continue`
- **Operator views season analytics**
  - `a season exists with watch data`
  - `I navigate to /admin/analytics/series/:series_id/seasons/:season_id`
  - `I see per-episode completion rates and drop-off analysis`

## `features/analytics__super_admin_platform_analytics.feature`

- **Super admin views platform-wide overview**
  - `I navigate to /super/analytics`
  - `I see platform-wide MRR, total organization count, and new signups over time`
- **Super admin views revenue by organization**
  - `I view the platform analytics`
  - `I see MRR broken down by organization`
- **Super admin views top-performing organizations**
  - `I view the platform analytics`
  - `I see a ranked list of top-performing organizations by subscriber count or MRR`

## `features/audit_logging__organization_audit_log.feature`

- **Operator views the audit log**
  - `who acted, when, what resource changed, and from which IP address`
- **Operator audit log captures impersonation context**
  - `a super admin impersonated an operator and made a change`
  - `I view the audit log entry for that change`
  - `I can see both the impersonating user and the acted-as user`

## `features/audit_logging__super_admin_platform_audit_log.feature`

- **Super admin views platform-wide audit log**
  - `I navigate to /super/audit-log`
  - `I see audit events across all organizations`
- **Super admin filters platform audit log by organization**
  - `the platform audit log has entries from multiple organizations`
  - `I filter by a specific organization`
  - `only entries from that organization are shown`
- **Super admin views super admin action in audit log**
  - `a super admin action such as granting super admin access occurred`
  - `I view the platform audit log`
  - `that action appears as an audit entry with the super admin as actor`

## `features/billing__coupon_management.feature`

- **Operator creates a fixed-amount coupon**
  - `I create a coupon with a code and a fixed discount amount`
  - `the coupon is available for viewers to apply at checkout`
- **Operator creates a percentage coupon**
  - `I create a coupon with a code and a percentage discount`
  - `the coupon reduces the plan price by that percentage at checkout`
- **Viewer applies a valid coupon at checkout**
  - `a coupon code exists and is active`
  - `a viewer enters the code during checkout`
  - `the discount is applied to the subscription price`
- **Viewer applies an invalid or expired coupon**
  - `an invalid or deactivated coupon code`
  - `a viewer enters the code during checkout`
  - `an error is displayed and no discount is applied`
- **Operator deactivates a coupon**
  - `an active coupon exists`
  - `I deactivate it`
  - `the coupon code can no longer be applied at checkout`

## `features/billing__stripe_connect_onboarding.feature`

- **Operator initiates Stripe Connect onboarding**
  - `my organization is not yet connected to Stripe`
  - `I click to connect my Stripe account`
  - `I am redirected to the Stripe OAuth flow`
- **Operator completes Stripe Connect onboarding**
  - `my organization is not yet connected to Stripe`
  - `I have completed the Stripe OAuth flow`
  - `Stripe redirects me back to the platform`
  - `my organization is linked to a Stripe Connect account`
  - `the Stripe Connect status shows as complete`
  - `I can receive viewer subscription payments`
- **Operator returns to Stripe Connect onboarding after interruption**
  - `my organization is not yet connected to Stripe`
  - `I started but did not complete Stripe Connect onboarding`
  - `I return via the Stripe refresh callback`
  - `I am redirected to continue onboarding`

## `features/billing__subscription_plan_management.feature`

- **Operator creates a subscription plan**
  - `I create a plan with a name, price, and description`
  - `a Stripe product and price are created in Stripe`
  - `the plan is available for viewers to subscribe to`
- **Operator creates a plan with a trial period**
  - `I create a plan and specify a trial duration`
  - `new subscribers receive a trial period before being charged`
- **Operator edits a subscription plan**
  - `a plan exists`
  - `I edit the plan name or description and save`
  - `the plan record is updated`
- **Operator deactivates a plan**
  - `an active plan exists with existing subscribers`
  - `I deactivate the plan`
  - `no new viewers can subscribe to it`
  - `existing subscribers retain their access`
- **Operator deletes a plan with no subscribers**
  - `a plan exists with no active subscribers`
  - `I delete the plan`
  - `it is removed from the system`

## `features/billing__viewer_subscription_flow.feature`

- **Viewer subscribes to a plan**
  - `I am a registered viewer on a tenant site`
  - `at least one active plan is available`
  - `I select a plan on the subscribe page`
  - `I am redirected to Stripe Checkout`
  - `upon successful payment my subscription becomes active`
  - `I gain access to gated content`
- **Viewer cancels checkout before completing payment**
  - `I am a registered viewer on a tenant site`
  - `I am on the Stripe Checkout page`
  - `I cancel and return to the platform`
  - `no subscription is created`
  - `I am returned to the subscribe page`
- **Viewer with an active subscription manages it**
  - `I am a registered viewer on a tenant site`
  - `I have an active subscription`
  - `I click "Manage Subscription" from my account page`
  - `I am redirected to the Stripe Customer Portal`
  - `I can update my payment method or cancel my subscription`
- **Viewer subscription is cancelled via portal**
  - `I am a registered viewer on a tenant site`
  - `I have an active subscription`
  - `I cancel through the Stripe Customer Portal`
  - `Stripe sends a cancellation webhook`
  - `my subscription status is updated to cancelled`
  - `I lose access to gated content at the end of the billing period`
- **Viewer subscription payment fails**
  - `I am a registered viewer on a tenant site`
  - `I have an active subscription`
  - `Stripe reports a failed payment via webhook`
  - `my account shows a payment issue notice`
  - `I am directed to resolve the issue`
- **Viewer resolves a payment failure**
  - `I am a registered viewer on a tenant site`
  - `my subscription has a payment failure`
  - `I update my payment method via the Stripe portal`
  - `payment succeeds`
  - `my subscription status returns to active`
  - `my access is restored`
- **Unauthenticated viewer attempts to access gated content**
  - `I am a registered viewer on a tenant site`
  - `a video requires a subscription`
  - `an unauthenticated viewer attempts to access it`
  - `they are redirected to the login or subscribe page`

## `features/branding__organization_branding_configuration.feature`

- **Operator sets a custom domain**
  - `I am on the organization settings page`
  - `I enter and save a custom domain`
  - `the organization is accessible at that custom domain`
- **Operator sets an admin accent color**
  - `I enter a custom color for the admin accent`
  - `save`
  - `the admin dashboard reflects the custom accent color`

## `features/branding__theme_and_color_customization.feature`

- **Operator overrides accent colors with custom values**
  - `I enter custom oklch or hex color values for accent color slots`
  - `save the appearance settings`
  - `the CSS variables are updated`
  - `the viewer site uses my custom colors`
- **Operator selects a display font**
  - `I choose a display font from the approved font list`
  - `save the appearance settings`
  - `the viewer site loads that font for headings`
- **Operator selects a body font**
  - `I choose a body font from the approved font list`
  - `save the appearance settings`
  - `the viewer site loads that font for body text`
- **Theme change propagates across cluster**
  - `I have saved a new theme`
  - `the save completes`
  - `a cache invalidation event is broadcast via PubSub`
  - `viewers see the updated theme without a server restart`
- **Operator previews a preset without applying**
  - `the live viewer site is not changed until I apply`
- **Operator expands preview to full screen**
  - `I click the expand preview button`
  - `a full-screen overlay appears`
  - `the overlay renders the canonical hero carousel component`
  - `the CTA buttons in the overlay match the viewer site exactly`
- **Operator dismisses the expanded preview**
  - `the full-screen preview overlay is open`
  - `I click the close button on the overlay`
  - `the overlay is dismissed`
  - `I return to the appearance editor`
- **Mini preview CTA buttons match viewer CTA styles**
  - `the primary CTA in the mini preview uses the hero-cta-primary CSS class`
  - `the secondary CTA in the mini preview uses the hero-cta-secondary CSS class`
  - `both CTAs reflect my configured accent color and text-on-accent color`

## `features/catalog__hero_banner_management.feature`

- **Operator creates a hero slide**
  - `I add a hero slide with a linked video and display metadata`
  - `the slide appears in the hero banner rotation on the viewer homepage`
- **Operator uploads a custom hero banner image**
  - `a hero slide exists`
  - `I upload a banner image for that slide`
  - `the image displays as the slide background`
- **Operator reorders hero slides**
  - `the hero has multiple slides`
  - `I reorder the slides`
  - `they rotate in the new order for viewers`
- **Operator sets the hero auto-advance interval**
  - `the hero banner is configured`
  - `I set an auto-advance interval in milliseconds`
  - `slides advance at that pace on the viewer homepage`
- **Operator toggles hero visibility**
  - `the hero banner is visible`
  - `I toggle hero visibility off`
  - `the hero banner is hidden from viewers`
- **Operator deletes a hero slide**
  - `a hero slide exists`
  - `I delete the slide`
  - `it is removed from the hero rotation`
- **Operator adds a title logo image to a hero slide**
  - `a hero slide exists`
  - `I enter a title logo URL for that slide`
  - `the viewer hero renders the title logo image instead of plain text`
- **Operator adds a channel logo to a hero slide**
  - `a hero slide exists`
  - `I enter a channel logo URL for that slide`
  - `the viewer hero renders the channel logo above the title area`
- **Hero slide without logo URLs falls back to text headline**
  - `a hero slide exists with no title logo or channel logo URL`
  - `a viewer sees the hero banner`
  - `the slide renders the text title and no logo images`
- **Both logo URLs are optional independently**
  - `a hero slide exists`
  - `I set only a channel logo URL and leave the title logo URL blank`
  - `the channel logo appears and the text headline is used for the title`

## `features/catalog__homepage_row_management.feature`

- **Operator adds videos to a row**
  - `a catalog row exists`
  - `I add videos to that row`
  - `those videos appear in the row on the viewer homepage`
- **Operator removes a video from a row**
  - `a catalog row has videos`
  - `I remove a video from the row`
  - `that video no longer appears in the row`
- **Operator toggles row visibility off**
  - `a catalog row exists`
  - `I toggle the row visibility off`
  - `viewers no longer see that row on the homepage`
- **Operator toggles row visibility on**
  - `a catalog row is hidden`
  - `viewers see the row on the homepage`
- **Operator edits a row title**
  - `a catalog row exists`
  - `I edit the row title and save`
  - `the updated title appears on the viewer homepage`
- **Operator deletes a catalog row**
  - `a catalog row exists`
  - `I delete the row`
  - `it is removed from the catalog`
  - `viewers no longer see it`

## `features/catalog__layout_presets.feature`

- **Operator loads a catalog preset**
  - `I select a layout preset such as cinema, learning, or creator`
  - `I confirm the overwrite`
  - `all existing rows are replaced with the preset configuration`
- **Operator cancels a preset load**
  - `I select a layout preset`
  - `I cancel before confirming the overwrite`
  - `my existing catalog rows remain unchanged`

## `features/catalog__row_card_display_options.feature`

- **Operator hides details below cards in a row**
  - `a catalog row exists with "Show details below card" enabled`
  - `I uncheck "Show details below card" for that row and save`
  - `cards in that row on the viewer homepage display without the details bar`
- **Operator re-enables details below cards**
  - `a catalog row has details hidden`
  - `I check "Show details below card" for that row and save`
  - `cards in that row display the details bar again`
- **Operator enables title overlay on cards**
  - `a catalog row has details hidden`
  - `I check "Overlay title on thumbnail" for that row and save`
  - `cards in that row show the title text overlaid on the thumbnail`
- **Title overlay option is only available when details are hidden**
  - `a catalog row exists with "Show details below card" enabled`
  - `I view the row editor`
  - `the "Overlay title on thumbnail" checkbox is not visible`
- **Disabling details and enabling overlay does not affect other rows**
  - `the catalog has two rows`
  - `I hide details and enable overlay on only one row`
  - `the other row still displays the details bar and no overlay`

## `features/content_consumption__content_discovery_and_browsing.feature`

- **Viewer browses the homepage**
  - `I am on a tenant viewer site`
  - `the organization has configured catalog rows and a hero banner`
  - `I navigate to the homepage`
  - `I see the hero banner and content rows as configured by the operator`
- **Unauthenticated viewer sees public content**
  - `I am on a tenant viewer site`
  - `I am not logged in`
  - `I navigate to the homepage`
  - `I see publicly visible content rows`
  - `I am prompted to log in or subscribe to access gated content`
- **Viewer browses a collection**
  - `I am on a tenant viewer site`
  - `a collection is visible on the platform`
  - `I navigate to the collection page`
  - `I see the collection's title and its videos`
- **Viewer filters content by tag**
  - `I am on a tenant viewer site`
  - `videos with various tags exist on the homepage`
  - `I select a tag filter`
  - `only videos with that tag are shown`
- **Viewer browses all content in a row**
  - `I am on a tenant viewer site`
  - `a catalog row exists with more items than fit in the default view`
  - `I click to view all items in that row`
  - `I see the full list of content in that row`

## `features/content_consumption__queue_management.feature`

- **Viewer adds a video to queue**
  - `I am logged in as a viewer`
  - `a video is available`
  - `I add it to my queue`
  - `it appears at the end of my queue`
- **Viewer adds a video to play next**
  - `I am logged in as a viewer`
  - `I have items in my queue and am currently watching`
  - `I add a video as "play next"`
  - `that video is inserted at the front of the queue`
- **Viewer removes an item from queue**
  - `I am logged in as a viewer`
  - `I have items in my queue`
  - `I remove one item`
  - `it is deleted from the queue`
  - `the remaining items maintain their order`
- **Viewer reorders queue items**
  - `I am logged in as a viewer`
  - `I have multiple items in my queue`
  - `I drag an item to a new position`
  - `the queue updates to reflect the new order`
- **Viewer clears the entire queue**
  - `I am logged in as a viewer`
  - `I have items in my queue`
  - `I clear the queue`
  - `all queue items are removed`
- **Viewer skips to the next item in queue**
  - `I am logged in as a viewer`
  - `I am watching a video and have items in my queue`
  - `I skip to the next video`
  - `the next queued item begins playing`
- **Viewer goes back to the previous queue item**
  - `I am logged in as a viewer`
  - `I have watched videos via the queue`
  - `I click "go back"`
  - `the previously watched video resumes from the beginning`
- **Viewer adds a collection to queue**
  - `I am logged in as a viewer`
  - `a collection exists with videos`
  - `I add the collection to my queue`
  - `the collection's videos are appended to my queue in order`

## `features/content_consumption__video_playback.feature`

- **Viewer plays a video**
  - `I am logged in as a viewer with an active subscription`
  - `a ready video exists`
  - `I navigate to the video watch page`
  - `the Mux player loads`
  - `playback begins`
- **Viewer playback progress is tracked**
  - `I am logged in as a viewer with an active subscription`
  - `I am watching a video`
  - `I pause or stop at a certain position`
  - `my playback position is saved`
- **Viewer resumes a video from last position**
  - `I am logged in as a viewer with an active subscription`
  - `I previously watched part of a video and my position was saved`
  - `I open the video again`
  - `playback starts from my last saved position`
- **Viewer dismisses a card from continue watching**
  - `I am logged in as a viewer with an active subscription`
  - `I have partially watched a video that appears in my continue watching row`
  - `I click the dismiss button on that video's card`
  - `the card is removed from my continue watching row`
  - `my playback progress for that video is not lost`
- **Dismissed card reappears after viewer watches again**
  - `I am logged in as a viewer with an active subscription`
  - `I have dismissed a video from my continue watching row`
  - `I watch that video again`
  - `the video reappears in my continue watching row`
- **Dismissing a series card hides the whole series**
  - `I am logged in as a viewer with an active subscription`
  - `I am watching an episode in a series`
  - `the series appears in my continue watching row`
  - `I click the dismiss button on the series card`
  - `the series no longer appears in my continue watching row`
  - `my progress in the series is not lost`
- **Viewer completes a video**
  - `I am logged in as a viewer with an active subscription`
  - `I am watching a video`
  - `the video plays to completion`
  - `the video is marked as completed in my watch history`
- **Viewer plays a series episode**
  - `I am logged in as a viewer with an active subscription`
  - `a series exists with at least one season and episode`
  - `I navigate to the series page`
  - `I see the episode list`
  - `I can play individual episodes`
- **Viewer switches seasons within a series**
  - `I am logged in as a viewer with an active subscription`
  - `a series has multiple seasons`
  - `I select a different season`
  - `the episode list updates to show episodes for that season`

## `features/content_consumption__watch_history.feature`

- **Viewer views watch history**
  - `I am logged in as a viewer`
  - `I have watched videos in the past`
  - `I navigate to /history`
  - `I see a chronological list of videos I have watched`
- **Viewer loads more history**
  - `I am logged in as a viewer`
  - `I have a long watch history spanning more than one page`
  - `I reach the bottom of the history list`
  - `more history items are loaded`
- **Viewer resumes from watch history**
  - `I am logged in as a viewer`
  - `a video appears in my watch history with a saved position`
  - `I click on it from history`
  - `playback resumes from my last saved position`

## `features/content_consumption__watchlist_and_favorites.feature`

- **Viewer adds a video to watchlist**
  - `I am logged in as a viewer`
  - `a video is available`
  - `I add it to my watchlist`
  - `it appears in my watchlist at /watchlist`
- **Viewer adds a series to watchlist**
  - `I am logged in as a viewer`
  - `a series is available`
  - `I add it to my watchlist`
  - `it appears in my watchlist`
- **Viewer removes an item from watchlist**
  - `I am logged in as a viewer`
  - `an item is in my watchlist`
  - `I remove it`
  - `it no longer appears in my watchlist`
- **Viewer favorites a video**
  - `I am logged in as a viewer`
  - `a video is available`
  - `I mark it as a favorite`
  - `it appears in my favorites at /favorites`
- **Viewer unfavorites a video**
  - `I am logged in as a viewer`
  - `a video is in my favorites`
  - `I remove it from favorites`
  - `it is removed from /favorites`

## `features/content_management__collections_management.feature`

- **Operator adds videos to a collection**
  - `a collection exists`
  - `I add videos to it`
  - `those videos appear as collection items in the correct order`
- **Operator adds a series to a collection**
  - `a collection and a series exist`
  - `I add the series to the collection`
  - `the series appears as a collection item`
- **Operator reorders collection items**
  - `a collection has multiple items`
  - `I move an item up or down`
  - `the display order is updated`
- **Operator removes an item from a collection**
  - `a collection has items`
  - `I remove an item`
  - `it is no longer part of that collection`
- **Operator toggles collection visibility**
  - `a collection exists`
  - `viewers cannot see the collection on the platform`
- **Operator makes a hidden collection visible**
  - `a collection is hidden`
  - `viewers can see the collection on the platform`
- **Operator soft-deletes a collection**
  - `a collection exists`
  - `I delete the collection`
  - `it is marked with a deleted_at timestamp`
  - `no longer appears to viewers`

## `features/content_management__series_and_season_management.feature`

- **Operator creates a season within a series**
  - `a series exists`
  - `I add a season with a name and season number`
  - `the season is created and linked to that series`
- **Operator edits a series**
  - `a series exists`
  - `I edit the series name or metadata and save`
  - `the series record is updated`
- **Operator edits a season**
  - `a season exists within a series`
  - `I edit the season details and save`
  - `the season record is updated`
- **Operator toggles series visibility**
  - `a series exists`
  - `viewers cannot see the series`
- **Operator toggles season visibility**
  - `a season exists`
  - `viewers cannot see that season`
- **Operator soft-deletes a series**
  - `a series exists`
  - `I delete the series`
  - `it is marked with a deleted_at timestamp`
  - `no longer appears to viewers`

## `features/content_management__tags_management.feature`

- **Operator edits a tag name**
  - `I edit its name and save`
  - `the tag name is updated`
  - `all videos with that tag reflect the updated name`

## `features/content_management__video_upload_and_management.feature`

- **Operator uploads a video**
  - `I select one or more video files and submit the upload form`
  - `the files are uploaded directly to Mux`
  - `I see real-time upload progress for each file`
  - `video records are created with status "processing"`
- **Video finishes processing in Mux**
  - `a video was uploaded and is processing in Mux`
  - `Mux signals the asset is ready via webhook`
  - `the video status updates to "ready"`
  - `the updated status is reflected in the content list without a page refresh`
- **Video encounters an error during processing**
  - `a video was uploaded and is processing in Mux`
  - `Mux signals an asset error via webhook`
  - `the video status updates to "error"`
  - `the operator can see the error state in the content list`
- **Operator uploads a video thumbnail**
  - `I upload a thumbnail image for that video`
  - `the thumbnail is stored and associated with the video`
- **Operator uploads a portrait thumbnail for a video**
  - `I upload a portrait thumbnail image for that video`
  - `the portrait thumbnail is stored and used for poster-style card displays`
- **Operator uploads a landscape thumbnail for a video**
  - `I upload a landscape thumbnail image for that video`
  - `the landscape thumbnail is stored and used for episode and hero card displays`
- **Video without uploaded thumbnails falls back to Mux smart-cropped URL**
  - `a video exists with no portrait or landscape thumbnail uploaded`
  - `the video is displayed on the viewer site`
  - `the player uses the Mux-generated thumbnail at the appropriate aspect dimensions`
- **Uploading a landscape thumbnail does not overwrite the portrait thumbnail**
  - `a video exists with both a portrait and a landscape thumbnail`
  - `I upload a new landscape thumbnail`
  - `the portrait thumbnail remains unchanged`
- **Operator adds a tag to a video**
  - `a video exists and tags are available`
  - `I add a tag to the video via the tag picker`
  - `the tag is associated with that video`
- **Operator creates and applies a new tag to a video**
  - `a video exists`
  - `I create a new tag and apply it to the video`
  - `the tag is created in the system`
  - `immediately associated with that video`
- **Operator removes a tag from a video**
  - `a video has an associated tag`
  - `I remove the tag from the video`
  - `the tag is disassociated from that video`
- **Operator searches videos**
  - `videos exist in the content library`
  - `I type a search query in the search box`
  - `the video list filters in real time to matching results`
- **Operator paginates the video list**
  - `more than one page of videos exists`
  - `the next set of videos is displayed`

## `features/live_events__live_event_calendar_export.feature`

- **Viewer downloads an ICS file for a scheduled event**
  - `an organization has a scheduled event with a known slug and start time`
  - `a viewer requests the calendar.ics file for that event`
  - `they receive a file with content-type text/calendar`
  - `the file has a content-disposition attachment header`
  - `the file contains a valid VCALENDAR with the event summary`
- **Viewer downloads an ICS file for a live event**
  - `an organization has a live event`
  - `a viewer requests the calendar.ics file for that event`
  - `they receive a valid ICS file`
- **ICS file uses CRLF line endings per RFC 5545**
  - `an organization has a scheduled event`
  - `a viewer downloads the ICS file`
  - `every line in the file ends with CRLF`
- **ICS DTEND reflects estimated_duration_minutes**
  - `a scheduled event with an estimated duration of 90 minutes starting at 10:00 UTC`
  - `a viewer downloads the ICS file`
  - `the DTEND is 11:30 UTC on the same day`
- **ICS uses 1-hour default duration when no estimate set**
  - `a scheduled event with no estimated duration`
  - `a viewer downloads the ICS file`
  - `the DTEND is 1 hour after the start time`
- **Calendar ICS returns 404 for ended events**
  - `an organization has an ended event`
  - `a viewer requests the calendar.ics file for that event`
  - `they receive a 404 response`
- **Calendar ICS returns 404 for canceled events**
  - `an organization has a canceled event`
  - `a viewer requests the calendar.ics file for that event`
  - `they receive a 404 response`
- **Calendar ICS returns 404 for a non-existent slug**
  - `an organization has no event with slug "no-such-event"`
  - `a viewer requests the calendar.ics file for that slug`
  - `they receive a 404 response`

## `features/live_events__live_event_google_calendar_link.feature`

- **Google Calendar URL is built with correct event details**
  - `a scheduled event with a title, slug, start time, and description`
  - `the Google Calendar URL is generated for that event and base URL`
  - `the URL starts with the Google Calendar render endpoint`
  - `the URL includes the event title, start time, and event page URL as location`
- **Google Calendar URL uses 1-hour default when no duration set**
  - `a scheduled event with no estimated duration`
  - `the Google Calendar URL is generated`
  - `the end time in the URL is 1 hour after the start time`

## `features/live_events__live_event_listing_viewer.feature`

- **Viewer sees live, upcoming, and past events grouped by status**
  - `an organization has a live event, a scheduled event, and an ended event`
  - `a viewer visits the events page for that organization`
  - `they see the live event in the live-now section`
  - `they see the scheduled event in the upcoming section`
  - `they see the ended event in the past section`
- **Live-now section shows a muted video preview when a playback ID exists**
  - `an organization has a live event with a Mux playback ID`
  - `a viewer visits the events page`
  - `the live event card embeds a muted autoplay video preview`
- **Live-now card falls back to cover image when no playback ID**
  - `an organization has a live event with a cover image but no playback ID`
  - `a viewer visits the events page`
  - `the live event card displays the cover image instead of a video preview`
- **Draft events are hidden from viewers**
  - `an organization has a draft event`
  - `a viewer visits the events page`
  - `the draft event is not visible`
- **Empty state renders when no events exist**
  - `an organization has no events`
  - `a viewer visits the events page`
  - `they see the empty state indicator`
- **Unauthenticated viewer can browse events**
  - `an organization has a scheduled event`
  - `an unauthenticated visitor views the events page`
  - `the page renders successfully without requiring login`
- **Authenticated operator can view their org events page**
  - `an operator is logged in to their organization`
  - `they visit the events page`
  - `the page renders successfully`

## `features/super_admin_org_management.feature`

- **Super admin lists all organizations**
  - `video count, subscriber count, and member count`

## `features/team_membership_management.feature`

- **Operator with owner role views team members**
  - `I am an organization owner`
  - `I see all members listed with their roles`
- **Operator with admin role views team members**
  - `I am an organization admin`
  - `I see all members listed with their roles`
- **Owner invites a new team member**
  - `I am an organization owner`
  - `I invite a user by email with a specified role`
  - `an invitation email is sent to that address`
  - `when the invitation is accepted the user joins with the specified role`
- **Owner removes a team member**
  - `I am an organization owner`
  - `a member exists in my organization`
  - `I remove that member`
  - `their membership is revoked`
  - `they lose access to the admin dashboard`
- **Non-owner cannot manage memberships**
  - `I am an organization editor`
  - `I attempt to manage team members`
  - `I am denied access`

## `features/viewer_management__operator_viewer_impersonation.feature`

- **Operator impersonates a viewer**
  - `a viewer exists in my organization`
  - `I choose to impersonate that viewer`
  - `I browse the viewer site as that viewer`
  - `the impersonation session is tracked with the operator and viewer IDs`
- **Operator ends viewer impersonation**
  - `I am impersonating a viewer`
  - `I end the impersonation session`
  - `I am returned to the operator dashboard`
  - `the viewer's session is not affected`

## `features/viewer_management__viewer_account_management.feature`

- **Viewer updates display name**
  - `I am logged in as a viewer`
  - `I edit my display name and save`
  - `my profile reflects the new display name`
- **Viewer updates avatar**
  - `I am logged in as a viewer`
  - `I upload a new avatar image and save`
  - `my profile reflects the new avatar`
- **Viewer updates marketing preferences**
  - `I am logged in as a viewer`
  - `I toggle my marketing opt-in preference and save`
  - `my marketing preference is updated`
- **Viewer deletes their account**
  - `I am logged in as a viewer`
  - `I confirm account deletion`
  - `my viewer account and all associated data are permanently removed`
  - `I am logged out`

## `features/viewer_management__viewer_registration_and_login.feature`

- **Viewer registers with email and password**
  - `the tenant site is accessible`
  - `I am an unauthenticated user on the tenant site`
  - `I submit the registration form with a valid email and password`
  - `a viewer account is created for my email`
  - `I am logged in`
- **Viewer registers with email only (magic link)**
  - `the tenant site is accessible`
  - `I am an unauthenticated user on the tenant site`
  - `I submit only my email address on the registration form`
  - `a viewer account is created`
  - `a magic link is sent to my email`
- **Viewer logs in via magic link**
  - `the tenant site is accessible`
  - `I have a viewer account`
  - `I enter my email on the login page`
  - `a magic link email is sent to me`
  - `clicking that link creates a session without requiring a password`
- **Viewer logs in with email and password**
  - `the tenant site is accessible`
  - `I have a viewer account with a password set`
  - `I submit valid credentials on the login page`
  - `I am logged in`
- **Viewer uses an expired magic link**
  - `the tenant site is accessible`
  - `a magic link token that has expired`
  - `I click the expired magic link`
  - `I see an error indicating the link is invalid or expired`
  - `no session is created`
- **Viewer logs out**
  - `the tenant site is accessible`
  - `I am logged in as a viewer`
  - `my session is invalidated`
  - `I am redirected to the login page`

## `features/webhooks__stripe_webhook_processing.feature`

- **Stripe sends subscription created event**
  - `a viewer just completed checkout`
  - `Stripe POSTs a customer.subscription.created event with a valid signature`
  - `the subscription record is created or updated for the viewer`
- **Stripe sends subscription updated event**
  - `a viewer has an active subscription`
  - `Stripe POSTs a customer.subscription.updated event`
  - `the subscription record is updated to reflect the new state`
- **Stripe sends subscription deleted event**
  - `a viewer has an active subscription`
  - `Stripe POSTs a customer.subscription.deleted event`
  - `the subscription is marked as cancelled`
  - `the viewer loses access to gated content at period end`
- **Stripe sends invoice payment succeeded event**
  - `a viewer's subscription has a pending invoice`
  - `Stripe POSTs invoice.payment_succeeded`
  - `the subscription status is confirmed as active`
- **Stripe sends invoice payment failed event**
  - `a viewer has an active subscription`
  - `Stripe POSTs invoice.payment_failed`
  - `the viewer's subscription status is marked as payment_failed`
  - `the viewer sees a payment issue notice`
- **Stripe webhook with invalid signature is rejected**
  - `Stripe POSTs a webhook with an invalid Stripe-Signature header`
- **Stripe Connect webhook is routed to the correct organization**
  - `an event concerns a Stripe Connect account linked to an organization`
  - `Stripe POSTs the webhook`
  - `the organization is resolved from the Connect account ID`
  - `processing is scoped to that organization`
