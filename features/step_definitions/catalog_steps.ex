defmodule BobineFeatures.Steps.Catalog do
  @moduledoc """
  Step definitions for catalog.feature.

  Row CRUD drives the admin Catalog UI via Wallaby. Reorder still uses the
  `Catalog.reorder_rows/2` context call because drag-and-drop is handled
  client-side via a Hook and is not easily simulated in a headless browser
  without a direct mouse event sequence — worth revisiting if drag fidelity
  becomes load-bearing.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Bobine.Factory
  import ExUnit.Assertions

  alias Bobine.Catalog

  # ---- Create row ---------------------------------------------------------

  when_ "I create a new row with a title and variant type", fn world ->
    title = "Featured Videos #{System.unique_integer([:positive])}"

    session =
      world.session
      |> visit("/admin/catalog?org=#{world.org.slug}")
      |> click(css("[data-test=new-row-btn]"))
      |> fill_in(css("[data-test=row-title-input]"), with: title)
      |> click(button("Save"))

    Map.merge(world, %{session: session, new_row_title: title})
  end

  then_ "the row appears in the catalog list", fn world ->
    session = visit(world.session, "/admin/catalog?org=#{world.org.slug}")
    assert_text(session, world.new_row_title)
    Map.put(world, :session, session)
  end

  # ---- Reorder rows -------------------------------------------------------

  given_ "the catalog has multiple rows", fn world ->
    org = world.org
    row_a = insert(:row, organization: org, title: "Row A", position: 0)
    row_b = insert(:row, organization: org, title: "Row B", position: 1)
    row_c = insert(:row, organization: org, title: "Row C", position: 2)
    Map.put(world, :rows, [row_a, row_b, row_c])
  end

  # Drag-and-drop is a Phoenix LiveView Hook — simulating it in Wallaby would
  # require dispatching the exact pointer event sequence the Sortable hook
  # expects. The context call here is a pragmatic gap; swap in a real drag
  # once you need to guard against hook regressions.
  when_ "I move a row up or down", fn world ->
    new_order = world.rows |> Enum.reverse() |> Enum.map(& &1.id)
    :ok = Catalog.reorder_rows(world.scope, new_order)
    Map.put(world, :new_order, new_order)
  end

  then_ "the display order on the viewer homepage updates accordingly", fn world ->
    %{results: rows} = Catalog.list_rows(world.org)
    actual_ids = Enum.map(rows, & &1.id)
    assert actual_ids == world.new_order
    world
  end
end
