defmodule Marquee.SubscriberDemo.Landing do
  @moduledoc "Read-only demo landing composition and explicit, non-overwriting template provisioning."
  import Ecto.Query

  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.Content.{Collection, CollectionItem, Video}
  alias Marquee.LandingPage
  alias Marquee.LandingPage.LandingSection
  alias Marquee.Repo
  alias Marquee.SubscriberDemo

  @doc "Loads configured sections, or ephemeral defaults when none exist. Requires database access; never writes."
  def sections(org) do
    %{results: configured} = LandingPage.list_landing_sections(org, per_page: 100)
    videos = approved_videos(org)

    sections =
      if configured == [] and not configured?(org),
        do: defaults(org, videos),
        else: configured

    Enum.map(sections, &fill_hero_image(&1, List.first(videos)))
  end

  @doc "Seeds only an entirely unconfigured demo landing page. Requires database access and writes audited landing sections."
  def seed(org) do
    Repo.transaction(fn ->
      current = Repo.one(from o in Organization, where: o.id == ^org.id, lock: "FOR UPDATE")

      cond do
        not SubscriberDemo.enabled?(current) -> Repo.rollback(:forbidden)
        configured?(current) -> :unchanged
        true -> seed_defaults(current)
      end
    end)
  end

  defp seed_defaults(org) do
    case defaults(org, approved_videos(org)) do
      [] ->
        Repo.rollback(:media_not_configured)

      sections ->
        Enum.each(sections, &create_section(org, &1))

        :seeded
    end
  end

  defp create_section(org, section) do
    attrs = Map.take(section, [:section_type, :position, :visible, :config])

    case LandingPage.create_landing_section(%Scope{organization: org}, attrs) do
      {:ok, _} -> :ok
      {:error, _, changeset} -> Repo.rollback(changeset)
    end
  end

  defp configured?(org),
    do:
      Repo.exists?(
        from s in LandingSection, where: s.organization_id == ^org.id and is_nil(s.deleted_at)
      )

  defp approved_videos(org) do
    ids = (org.features || %{})["subscriber_demo_video_ids"] || []

    videos =
      Repo.all(
        from v in Video,
          where:
            v.organization_id == ^org.id and v.id in ^ids and v.published and
              v.mux_status == "ready" and is_nil(v.deleted_at) and
              not is_nil(v.mux_playback_id) and v.mux_playback_id not in ["", "pending"],
          limit: 24
      )

    by_id = Map.new(videos, &{&1.id, &1})
    ids |> Enum.take(24) |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1)
  end

  defp defaults(_org, []), do: []

  defp defaults(org, [first | _] = videos) do
    rows =
      org
      |> collections(videos)
      |> Enum.map(fn collection ->
        {:content_row,
         %{
           "source_type" => "collection",
           "source_id" => collection.id,
           "title" => collection.title,
           "max_items" => 12
         }}
      end)

    ([
       {:hero_image,
        %{
          "image_url" => thumbnail(first),
          "headline" => "Make time for the creative process.",
          "subheadline" =>
            "Step inside #{org.name}. Discover thoughtful work, follow a series, and find something worth making.",
          "show_cta" => false
        }},
       {:marketing_copy,
        %{
          "headline" => "Small details. Satisfying discoveries.",
          "body" =>
            "A closer look at people making things. Explore the collection, save your favorites, and return to the moments that inspire you.",
          "text_alignment" => "left"
        }}
     ] ++
       rows ++
       [
         {:faq,
          %{
            "items" => [
              %{
                "question" => "What can I try?",
                "answer" =>
                  "Watch the videos, explore a series, and make your own watchlist. Your demo is private to this browser."
              },
              %{
                "question" => "Do I need an account or payment details?",
                "answer" => "No. Begin the demo to explore for two hours, without signing up."
              }
            ]
          }}
       ])
    |> Enum.with_index()
    |> Enum.map(fn {{type, config}, position} ->
      %LandingSection{
        id: "demo-default-#{position}",
        organization_id: org.id,
        section_type: type,
        position: position,
        visible: true,
        config: config
      }
    end)
  end

  defp collections(org, videos) do
    ids = Enum.map(videos, & &1.id)

    Repo.all(
      from c in Collection,
        join: item in CollectionItem,
        on: item.collection_id == c.id and item.organization_id == ^org.id,
        where:
          c.organization_id == ^org.id and c.visible and is_nil(c.deleted_at) and
            item.video_id in ^ids,
        distinct: true,
        order_by: [asc: c.inserted_at, asc: c.id],
        limit: 2
    )
  end

  defp fill_hero_image(%{section_type: :hero_image} = section, video) when not is_nil(video) do
    if section.config["image_url"] in [nil, ""],
      do: %{section | config: Map.put(section.config, "image_url", thumbnail(video))},
      else: section
  end

  defp fill_hero_image(section, _video), do: section

  defp thumbnail(video),
    do:
      video.landscape_thumbnail_url ||
        "https://image.mux.com/#{URI.encode_www_form(video.mux_playback_id)}/thumbnail.jpg?width=1600"
end
