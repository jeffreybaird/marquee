# Separation of Concerns — LiveViews and Context Functions

Load this file when writing or modifying any LiveView, controller, or
context function. This is the rule that keeps the codebase ready for a
GraphQL API, native mobile apps, or any future transport layer.

---

## The Rule

**LiveViews are thin controllers. Context functions are the application.**

A LiveView's job is:
1. Mount — load initial data by calling context functions
2. Render — present data from assigns using templates
3. Handle events — translate user actions into context function calls
4. Handle info — react to PubSub messages by updating assigns

A LiveView must NEVER:
- Call `Repo` directly
- Build Ecto queries
- Contain business rules (domain validation, authorization, state machine logic)
- Perform data aggregation or transformation that a future API would also need
- Execute multi-step operations that should be atomic

**The test: could a GraphQL resolver do this same operation by calling the
same context function with the same arguments?** If the answer is no because
the logic is trapped inside a LiveView, the separation has been violated.

---

## What belongs where

### In the context function

- Database queries (all Repo calls)
- Business rules ("a video can only be published if its status is ready")
- Authorization ("only admin+ can delete videos")
- Data aggregation ("count videos by status for this org")
- Multi-step operations ("create video, add to collection, and tag it")
- External API calls (Mux, Stripe — through client behaviours)
- Event broadcasting
- Audit logging
- Metrics emission
- Error handling with tagged tuples

### In the LiveView

- Extracting parameters from events (`%{"id" => id}`)
- Calling context functions with those parameters
- Pattern matching on context function results to decide what to render
- Assigning data to the socket
- Setting flash messages based on error atoms
- Navigating/redirecting
- Subscribing to PubSub topics
- Updating assigns when PubSub messages arrive
- UI-only state (modal open/closed, tab selection, form changeset tracking)

### The gray area — presenter/formatter logic

Formatting data for display (e.g. formatting seconds as "mm:ss", building
a thumbnail URL from a playback ID, formatting currency) lives in a
**view helper or component**, not in the context and not inline in the
LiveView's `handle_event`. These are presentation concerns.

```elixir
# ✅ In a helper/component module
def format_duration(seconds) when is_number(seconds) do
  minutes = trunc(seconds / 60)
  secs = trunc(rem(trunc(seconds), 60))
  "#{minutes}:#{String.pad_leading("#{secs}", 2, "0")}"
end

def mux_thumbnail_url(playback_id, opts \\ []) do
  width = Keyword.get(opts, :width, 400)
  height = Keyword.get(opts, :height, 225)
  "https://image.mux.com/#{playback_id}/thumbnail.webp?width=#{width}&height=#{height}"
end
```

---

## Patterns

### Correct: simple event → context call → assign result

```elixir
def handle_event("delete_video", %{"id" => id}, socket) do
  video = Content.get_video!(socket.assigns.organization, id)

  case Content.delete_video(socket.assigns.current_scope, video) do
    {:ok, _deleted} ->
      {:noreply,
       socket
       |> put_flash(:info, "Video deleted.")
       |> push_navigate(to: ~p"/admin/content")}

    {:error, :forbidden} ->
      {:noreply, put_flash(socket, :error, "You don't have permission to delete this video.")}
  end
end
```

### Correct: mount loads data via context, no transformation

```elixir
def mount(_params, _session, socket) do
  org = socket.assigns.organization

  %{results: videos} = Content.list_videos(org, per_page: 25)
  stats = Content.video_stats(org)
  hero_slides = Catalog.resolve_hero_slides_cached(org)

  {:ok, assign(socket,
    videos: videos,
    stats: stats,
    hero_slides: hero_slides,
    page_title: org.name
  )}
end
```

### Correct: PubSub handler updates a single assign

```elixir
def handle_info({:marquee_event, {:video_ready, video}, _scope}, socket) do
  {:noreply, update_video_in_list(socket, video)}
end

defp update_video_in_list(socket, updated_video) do
  videos = Enum.map(socket.assigns.videos, fn v ->
    if v.id == updated_video.id, do: updated_video, else: v
  end)
  assign(socket, videos: videos)
end
```

### Violation: business rule leaked into LiveView

```elixir
# ❌ The "can only publish if ready" rule belongs in the context
def handle_event("publish", %{"id" => id}, socket) do
  video = Content.get_video!(socket.assigns.organization, id)

  if video.mux_status == "ready" do
    Content.update_video(socket.assigns.current_scope, video, %{published: true})
    {:noreply, put_flash(socket, :info, "Published.")}
  else
    {:noreply, put_flash(socket, :error, "Video must be ready to publish.")}
  end
end
```

Fix: create `Content.publish_video(scope, video)` that checks the status
internally and returns `{:error, :not_ready}` if it fails.

### Violation: Repo call in LiveView

```elixir
# ❌ Direct database access
def mount(_params, _session, socket) do
  videos = Repo.all(
    from v in Video,
    where: v.organization_id == ^socket.assigns.organization.id,
    where: is_nil(v.deleted_at),
    order_by: [desc: :inserted_at]
  )
  {:ok, assign(socket, videos: videos)}
end
```

Fix: call `Content.list_videos(organization)`.

### Violation: multi-step operation in LiveView

```elixir
# ❌ Three context calls that should be one atomic operation
def handle_event("quick_publish", params, socket) do
  {:ok, video} = Content.create_video(scope, params)
  {:ok, _} = Content.add_video_to_collection(scope, featured_collection, video)
  {:ok, _} = Content.publish_video(scope, video)
  {:noreply, ...}
end
```

Fix: create `Content.create_and_publish_video(scope, params, collection)` that
wraps all three in a transaction.

---

## When context functions need to be created

If an audit or a new feature reveals that a LiveView needs to do something
that no context function supports, create the context function first:

1. Define the function in the appropriate context module
2. Implement the business logic
3. Add a `@doc` with a doctest
4. Wrap in `Telemetry.with_span`
5. Broadcast events if mutating
6. Return tagged tuples
7. Write tests
8. THEN call it from the LiveView

Never skip steps 1-7 and just put the logic in the LiveView "temporarily."
Temporary code in LiveViews becomes permanent debt the moment you need a
GraphQL API or a mobile app.

---

## Checklist for every LiveView change

Before committing changes to any LiveView:

- [ ] No `Repo.` calls in the module
- [ ] No `Ecto.Changeset.` calls (except assigning form changesets)
- [ ] No `from(` or `|> where(` query building
- [ ] No business rule conditionals in `handle_event`
- [ ] No multi-step context call sequences in `handle_event`
- [ ] No direct role/permission checks
- [ ] No data aggregation that a GraphQL resolver would also need
- [ ] Every context function called exists and has tests
- [ ] Every error case from context functions is handled in the LiveView