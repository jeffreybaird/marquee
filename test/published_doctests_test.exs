for {documented_module, case_module} <- Marquee.PublishedDoctests.registrations() do
  Module.create(
    Module.concat(documented_module, PublishedExamplesTest),
    quote do
      use unquote(case_module), async: false

      # Keep each target's imports isolated, and execute all examples. Existing
      # focused doctests elsewhere do not replace this complete registration.
      doctest unquote(documented_module), import: true
    end,
    Macro.Env.location(__ENV__)
  )
end

defmodule Marquee.PublishedDoctestCoverageTest do
  use ExUnit.Case, async: false

  test "every compiled module publishing IEx examples has an unfiltered registration" do
    registered = Enum.map(Marquee.PublishedDoctests.registrations(), &elem(&1, 0))
    assert length(registered) == length(Enum.uniq(registered))
    assert Enum.sort(registered) == Marquee.PublishedDoctests.documented_modules()
  end

  test "only wholly generated entry documentation is excluded from authored coverage" do
    doc = %{"en" => "    iex> 1 + 1\n    2"}
    entry = fn metadata -> {{:function, :example, 0}, 1, ["example()"], doc, metadata} end
    generated = entry.(%{source_annos: [[generated: true, location: 1]]})
    refute Marquee.PublishedDoctests.authored_examples?(:none, [generated])

    for metadata <- [
          %{},
          %{source_annos: []},
          %{source_annos: [[generated: false]]},
          %{source_annos: [[generated: true], [location: 2]]}
        ] do
      assert Marquee.PublishedDoctests.authored_examples?(:none, [entry.(metadata)])
    end

    assert Marquee.PublishedDoctests.authored_examples?(doc, [generated])
    {:docs_v1, _, _, _, repo_doc, _, repo_entries} = Code.fetch_docs(Marquee.Repo)
    refute Marquee.PublishedDoctests.authored_examples?(repo_doc, repo_entries)
    assert Marquee.PublishedDoctests.authored_examples?(repo_doc, [entry.(%{}) | repo_entries])
  end
end
