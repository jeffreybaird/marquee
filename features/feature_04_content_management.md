# Task: Feature 04 — Content Management (Collections, Tags, Catalog Rows)

This feature builds the content organization layer. Operators group videos into
collections, tag them for discovery, and arrange catalog rows to compose their
viewer-facing homepage. This is what turns a flat list of videos into a curated
streaming experience.

Follow all rules in CLAUDE.md — especially Architecture Principles 1, 3, 5, 7,
8, 9, and 10. Load `.claude/architecture-decisions.md`, `.claude/observability.md`,
`.claude/scalability.md`, `.claude/testing.md`, and `.claude/multi-tenancy.md`.

This task has 7 parts. Do them in order. Run `mix test` after each part.

---

## Part 1: Collections Context

Collections are named groups of videos — like "Season 1", "Yoga Fundamentals",
or "Behind the Scenes". A video can belong to multiple collections. Collections
have an ordered list of videos.

### Schema: `Collection`

Should already exist from initial scaffolding. Verify it has:

```elixir
schema "collections" do
  belongs_to :organization, Organization
  field :title, :string
  field :slug, :string
  field :description, :string
  field :cover_image_url, :string
  field :position, :integer, default: 0
  field :visible, :boolean, default: true
  field :deleted_at, :utc_datetime

  has_many :collection_items, CollectionItem
  many_to_many :videos, Video, join_through: CollectionItem

  timestamps(type: :utc_datetime)
end
```

### Schema: `CollectionItem` (join table)

```elixir
schema "collection_items" do
  belongs_to :organization, Organization
  belongs_to :collection, Collection
  belongs_to :video, Video
  field :position, :integer, default: 0

  timestamps(type: :utc_datetime)
end
```

The `position` field on `CollectionItem` controls the video order within the
collection. The `position` field on `Collection` controls the display order
of collections themselves.

### Migration

If the tables don't exist yet, generate them:

```bash
mix ecto.gen.migration create_collections_and_collection_items
```

- `collections`: unique index on `[:organization_id, :slug]`
- `collection_items`: unique index on `[:collection_id, :video_id]`, index on `[:organization_id]`

### Content context functions

Add to `Bobine.Content` (or create `Bobine.Content.Collections` if the context
is getting large — but keep it under the `Content` namespace):

```elixir
# Collections
def list_collections(organization, opts \\ [])
def get_collection(organization, id)
def get_collection!(organization, id)
def create_collection(scope, attrs)
def update_collection(scope, collection, attrs)
def delete_collection(scope, collection)  # soft delete
def restore_collection(scope, collection)
def reorder_collections(scope, ordered_ids)

# Collection items (videos within a collection)
def list_collection_videos(organization, collection, opts \\ [])
def add_video_to_collection(scope, collection, video, position \\ nil)
def remove_video_from_collection(scope, collection, video)
def reorder_collection_videos(scope, collection, ordered_video_ids)
```

### Rules

- All functions scoped to `organization_id` — no cross-tenant access
- All list functions return pagination structs
- All mutations broadcast events: `:collection_created`, `:collection_updated`,
  `:collection_deleted`, `:collection_video_added`, `:collection_video_removed`,
  `:collection_videos_reordered`
- All mutations wrapped in `Telemetry.with_span`
- Soft deletes on collections (not on collection items — removing is immediate)
- Slug auto-generated from title, unique per org
- `reorder_collections/2` accepts a list of collection IDs in the desired order
  and updates all positions in a single transaction
- `reorder_collection_videos/3` same pattern within a collection

---

## Part 2: Tags Context

Tags are lightweight labels for filtering and search. An operator creates tags
like "Beginner", "Advanced", "Live Session", "Interview". Videos can have
multiple tags.

### Schema: `Tag`

```elixir
schema "tags" do
  belongs_to :organization, Organization
  field :name, :string
  field :slug, :string
  field :deleted_at, :utc_datetime

  many_to_many :videos, Video, join_through: "video_tags"

  timestamps(type: :utc_datetime)
end
```

### Schema: `VideoTag` (join table)

```elixir
schema "video_tags" do
  belongs_to :organization, Organization
  belongs_to :video, Video
  belongs_to :tag, Tag

  timestamps(type: :utc_datetime)
end
```

### Migration

- `tags`: unique index on `[:organization_id, :slug]`
- `video_tags`: unique index on `[:video_id, :tag_id]`, index on `[:organization_id]`

### Content context functions

```elixir
# Tags
def list_tags(organization, opts \\ [])
def get_tag(organization, id)
def create_tag(scope, attrs)
def update_tag(scope, tag, attrs)
def delete_tag(scope, tag)  # soft delete

# Video tagging
def tag_video(scope, video, tag)
def untag_video(scope, video, tag)
def list_video_tags(organization, video)
def list_videos_by_tag(organization, tag, opts \\ [])
```

### Rules

- Tag names are case-insensitive — normalize to lowercase on create
- Slug auto-generated from name
- Duplicate tag names per org return `{:error, :already_exists}`
- All mutations broadcast events and log audit entries
- Deleting a tag soft-deletes it and removes all video_tag associations

---

## Part 3: Catalog Rows Context

Catalog rows define the viewer-facing homepage layout. Each row is a horizontal
strip of content — like "Trending", "New Releases", "Continue Watching",
"Yoga Basics". Rows can be manually curated (operator picks specific videos)
or dynamic (auto-populated by tag, collection, recency, or watch history).

### Schema: `Row`

Should already exist. Verify:

```elixir
schema "rows" do
  belongs_to :organization, Organization
  field :title, :string
  field :source_type, Ecto.Enum, values: [:curated, :collection, :tag, :recent, :continue_watching, :popular]
  field :source_id, :binary_id        # references a collection or tag ID when source_type is :collection or :tag
  field :position, :integer, default: 0
  field :visible, :boolean, default: true
  field :max_items, :integer, default: 20
  field :deleted_at, :utc_datetime

  has_many :row_items, RowItem

  timestamps(type: :utc_datetime)
end
```

### Schema: `RowItem`

For curated rows, each item is a manually selected video in a specific position:

```elixir
schema "row_items" do
  belongs_to :organization, Organization
  belongs_to :row, Row
  belongs_to :video, Video
  field :position, :integer, default: 0
  field :deleted_at, :utc_datetime

  timestamps(type: :utc_datetime)
end
```

### Catalog context functions

Create `Bobine.Catalog`:

```elixir
# Rows
def list_rows(organization, opts \\ [])
def get_row(organization, id)
def create_row(scope, attrs)
def update_row(scope, row, attrs)
def delete_row(scope, row)  # soft delete
def reorder_rows(scope, ordered_ids)

# Row items (for curated rows)
def list_row_items(organization, row, opts \\ [])
def add_item_to_row(scope, row, video, position \\ nil)
def remove_item_from_row(scope, row, video)
def reorder_row_items(scope, row, ordered_video_ids)

# Row content resolution (for all row types)
def resolve_row_content(organization, row, opts \\ [])
```

### `resolve_row_content/3` — the key function

This function returns the videos for a row regardless of source type:

```elixir
def resolve_row_content(organization, row, opts \\ []) do
  case row.source_type do
    :curated ->
      # Return videos from row_items, ordered by position
      list_row_items(organization, row, opts)

    :collection ->
      # Return videos from the referenced collection
      Content.list_collection_videos(organization, %{id: row.source_id}, opts)

    :tag ->
      # Return videos with the referenced tag
      Content.list_videos_by_tag(organization, %{id: row.source_id}, opts)

    :recent ->
      # Return most recently published videos
      Content.list_videos(organization, Keyword.merge(opts, order_by: [desc: :inserted_at]))

    :popular ->
      # Return most-viewed videos (placeholder — needs analytics data)
      # For now, fall back to recent
      Content.list_videos(organization, Keyword.merge(opts, order_by: [desc: :inserted_at]))

    :continue_watching ->
      # Per-viewer — requires user context, returns videos with saved progress
      # Placeholder for Feature 06
      %{results: [], page: 1, per_page: 25, total: 0, total_pages: 1}
  end
end
```

### Cache row content for viewer-facing pages

Row content for non-personalized rows (curated, collection, tag, recent, popular)
should be cached per org since it changes infrequently:

```elixir
def resolve_row_content_cached(organization, row, opts \\ []) do
  case row.source_type do
    :continue_watching ->
      # Personalized — never cache
      resolve_row_content(organization, row, opts)

    _ ->
      Cache.fetch("row_content:#{organization.id}:#{row.id}", ttl: :timer.minutes(1), fn ->
        resolve_row_content(organization, row, opts)
      end)
  end
end
```

### Rules

- Rows are ordered by `position` — the operator controls the homepage layout
- `reorder_rows/2` updates all positions in a single transaction
- Dynamic rows (collection, tag, recent, popular) have no row_items — content
  is resolved at render time
- Curated rows use row_items for explicit video selection and ordering
- `source_id` is only used when `source_type` is `:collection` or `:tag`
- All mutations broadcast events and invalidate the relevant cache keys
- Cache invalidation must happen when: a row is updated, a video is added
  to a collection referenced by a row, a tag is applied to a video referenced
  by a row

---

## Part 4: Collections Admin LiveView

Build out `/admin/content/collections` (or extend `/admin/catalog` depending
on where it fits best in the nav — collections are content, rows are catalog).

### Collections list page

- Table of collections with: title, video count, visibility toggle, position
- "New Collection" button
- Drag-and-drop reorder (or up/down arrow buttons for simpler implementation)
- Click a collection to view/edit it

### Collection detail/edit page

- Edit title, description, cover image URL
- Visibility toggle
- Video list within the collection (ordered by position)
- "Add Videos" action — opens a picker showing org videos not yet in the collection
- Drag-and-drop reorder of videos within the collection (or up/down arrows)
- Remove video from collection

### `data-test` attributes

- `data-test="collections-list"`
- `data-test={"collection-row-#{id}"}`
- `data-test="new-collection-btn"`
- `data-test={"collection-video-#{video.id}"}`
- `data-test="add-videos-btn"`
- `data-test={"remove-video-#{video.id}"}`
- `data-test="collection-title-input"`
- `data-test="collection-visibility-toggle"`

---

## Part 5: Tags Admin UI

Tags can live as a section within the content management page or as their own
page. Keep it simple.

### Tag management

- List of existing tags for the org
- "New Tag" input (inline — type name, press enter or click add)
- Delete tag button (with confirmation)
- Edit tag name (inline edit)

### Video tagging

On the video edit/detail page (extend the content management UI from Feature 03):
- Show current tags as pills/badges
- "Add Tag" dropdown or autocomplete showing available tags
- Click X on a tag pill to remove it

### `data-test` attributes

- `data-test="tags-list"`
- `data-test={"tag-#{tag.id}"}`
- `data-test="new-tag-input"`
- `data-test={"delete-tag-#{tag.id}"}`
- `data-test={"video-tag-#{tag.id}"}`
- `data-test="add-tag-selector"`

---

## Part 6: Catalog Rows Admin LiveView

Build out `/admin/catalog` as the homepage layout builder.

### Row list page

- List of rows in position order
- Each row shows: title, source type label, visibility, item count
- "New Row" button
- Drag-and-drop reorder of rows (or up/down arrows)
- Click to edit a row

### Row edit page

- Title input
- Source type selector (curated, collection, tag, recent, popular, continue_watching)
- When source type is `collection`: dropdown to select a collection
- When source type is `tag`: dropdown to select a tag
- When source type is `curated`: video picker and reorder interface (same as collection detail)
- Max items slider or input (5–50)
- Visibility toggle
- Preview of resolved content (show the first few video thumbnails)

### `data-test` attributes

- `data-test="rows-list"`
- `data-test={"row-#{row.id}"}`
- `data-test="new-row-btn"`
- `data-test="row-source-type-select"`
- `data-test="row-source-id-select"`
- `data-test="row-title-input"`
- `data-test="row-visibility-toggle"`
- `data-test="row-preview"`

---

## Part 7: Tests

### Context tests

**`test/bobine/content/collections_test.exs`**
- `list_collections/2` returns only the org's collections
- `list_collections/2` excludes soft-deleted collections
- `list_collections/2` returns pagination struct
- `create_collection/2` with valid attrs succeeds
- `create_collection/2` generates slug from title
- `create_collection/2` with duplicate slug in same org returns error
- `create_collection/2` with duplicate slug in different org succeeds
- `delete_collection/2` sets deleted_at
- `reorder_collections/2` updates positions in order
- `add_video_to_collection/3` creates association
- `add_video_to_collection/3` with duplicate video returns `{:error, :already_exists}`
- `remove_video_from_collection/3` removes association
- `reorder_collection_videos/3` updates positions
- `list_collection_videos/3` returns videos in position order

**`test/bobine/content/tags_test.exs`**
- `list_tags/2` returns only the org's tags
- `create_tag/2` normalizes name to lowercase
- `create_tag/2` with duplicate name returns error
- `delete_tag/2` soft-deletes and removes video associations
- `tag_video/3` creates association
- `untag_video/3` removes association
- `list_videos_by_tag/3` returns correct videos

**`test/bobine/catalog/catalog_test.exs`**
- `list_rows/2` returns rows in position order
- `create_row/2` with all source types succeeds
- `delete_row/2` soft-deletes
- `reorder_rows/2` updates positions
- `resolve_row_content/3` for curated row returns row_items in order
- `resolve_row_content/3` for collection row returns collection videos
- `resolve_row_content/3` for tag row returns tagged videos
- `resolve_row_content/3` for recent row returns videos newest-first
- `resolve_row_content/3` for continue_watching returns empty (placeholder)

**Multi-tenant isolation tests (for each context):**
- Org A's collections/tags/rows are not visible to org B
- Org A's video cannot be added to org B's collection
- Org A's tag cannot be applied to org B's video

### LiveView tests

**`test/bobine_web/live/admin/collections_live_test.exs`**
- Page renders collection list
- Empty state when no collections
- Create collection with valid data
- Create collection with missing title shows error
- Duplicate slug shows error
- Add video to collection
- Remove video from collection
- Delete collection removes it from list
- Collections from other orgs not visible
- Editor role can manage collections
- Viewer_support role has read-only access

**`test/bobine_web/live/admin/catalog_live_test.exs`**
- Page renders row list in position order
- Create curated row
- Create collection-based row with source selection
- Create tag-based row with source selection
- Create recent row (no source selection needed)
- Edit row title and source type
- Delete row removes it from list
- Row preview shows resolved content
- Rows from other orgs not visible
- Reorder updates positions

---

## Definition of Done

- [ ] Collection schema, migration, and context functions
- [ ] CollectionItem join table with position ordering
- [ ] Tag schema, migration, and context functions
- [ ] VideoTag join table with case-insensitive name handling
- [ ] Catalog context with Row and RowItem management
- [ ] `resolve_row_content/3` handles all source types
- [ ] Row content cached for non-personalized rows with event-driven invalidation
- [ ] Collections admin page with CRUD, video picker, and reordering
- [ ] Tags admin UI with inline creation, editing, and video tagging
- [ ] Catalog rows admin page with source type selection and preview
- [ ] Reorder functions use single-transaction position updates
- [ ] All context functions wrapped in OTel spans
- [ ] All mutations broadcast events via `Bobine.Events`
- [ ] All mutations generate audit log entries
- [ ] All list functions return pagination structs
- [ ] All error returns use tagged tuples
- [ ] Soft deletes on collections, tags, rows, row_items
- [ ] Slugs auto-generated and unique per org
- [ ] Multi-tenant isolation verified in tests
- [ ] RBAC enforced (editor+ for mutations, viewer_support for read)
- [ ] `data-test` attributes on all interactive elements
- [ ] `export_organization_data/1` updated to include collections, tags, rows
- [ ] `mix format`, `mix credo --strict`, `mix dialyzer` pass
- [ ] `npx tsc --noEmit` passes
- [ ] All tests pass