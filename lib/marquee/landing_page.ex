defmodule Marquee.LandingPage do
  @moduledoc """
  The LandingPage context.

  Manages the configurable marketing landing page that logged-out visitors see
  on an organization's site. The page is composed of ordered `LandingSection`
  records, each with a typed config that drives a specific renderer.

  Section types: `:hero_video`, `:hero_image`, `:hero_slider`, `:marketing_copy`,
  `:content_row`, `:plan_display`, `:header_text`, `:faq`.
  """

  import Ecto.Query, warn: false

  alias Marquee.Accounts.Organization
  alias Marquee.Audit
  alias Marquee.Billing
  alias Marquee.Catalog
  alias Marquee.Content
  alias Marquee.Events
  alias Marquee.LandingPage.LandingSection
  alias Marquee.Pagination
  alias Marquee.Repo

  require Marquee.Otel

  ## -----------------------------------------------------------------------
  ## Reads
  ## -----------------------------------------------------------------------

  @doc """
  Paginated list of visible, non-deleted landing sections for an organization,
  ordered by position.

  Exempt from doctest — hits the database.
  """
  def list_landing_sections(%Organization{id: org_id}, opts \\ []) do
    LandingSection
    |> where(organization_id: ^org_id)
    |> where([s], is_nil(s.deleted_at))
    |> where([s], s.visible == true)
    |> order_by(asc: :position)
    |> Pagination.paginate(opts)
  end

  @doc """
  Paginated list of ALL landing sections (including hidden) for admin editing,
  ordered by position. Excludes soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_landing_sections_admin(%Organization{id: org_id}, opts \\ []) do
    LandingSection
    |> where(organization_id: ^org_id)
    |> where([s], is_nil(s.deleted_at))
    |> order_by(asc: :position)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a landing section within an organization.

  Returns `{:ok, section}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_landing_section(%Organization{id: org_id}, id) do
    case Repo.get_by(LandingSection, id: id, organization_id: org_id) do
      nil -> {:error, :not_found}
      section -> {:ok, section}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking landing section changes.

  ## Examples

      iex> change_landing_section(%Marquee.LandingPage.LandingSection{})
      %Ecto.Changeset{data: %Marquee.LandingPage.LandingSection{}}
  """
  def change_landing_section(%LandingSection{} = section, attrs \\ %{}) do
    LandingSection.changeset(section, attrs)
  end

  ## -----------------------------------------------------------------------
  ## Writes
  ## -----------------------------------------------------------------------

  @doc """
  Creates a landing section under the scope's organization.

  Exempt from doctest — hits the database.
  """
  def create_landing_section(scope, attrs) do
    Marquee.Otel.with_span "marquee.landing_page.create_landing_section",
                           %{"marquee.org.id" => scope.organization.id} do
      attrs =
        attrs
        |> stringify_top_keys()
        |> Map.put("organization_id", scope.organization.id)
        |> ensure_position(scope.organization)

      case %LandingSection{} |> LandingSection.changeset(attrs) |> Repo.insert() do
        {:ok, section} ->
          Events.broadcast(scope, {:landing_section_created, section})
          Audit.log(scope, "landing_section.created", section)
          {:ok, section}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a landing section's config and/or visibility.

  Exempt from doctest — hits the database.
  """
  def update_landing_section(scope, %LandingSection{} = section, attrs) do
    Marquee.Otel.with_span "marquee.landing_page.update_landing_section",
                           %{"marquee.org.id" => scope.organization.id} do
      case section |> LandingSection.changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          Events.broadcast(scope, {:landing_section_updated, updated})
          Audit.log(scope, "landing_section.updated", updated, attrs)
          {:ok, updated}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a landing section.

  Exempt from doctest — hits the database.
  """
  def delete_landing_section(scope, %LandingSection{} = section) do
    Marquee.Otel.with_span "marquee.landing_page.delete_landing_section",
                           %{"marquee.org.id" => scope.organization.id} do
      section
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()
      |> case do
        {:ok, deleted} ->
          Events.broadcast(scope, {:landing_section_deleted, deleted})
          Audit.log(scope, "landing_section.deleted", deleted)
          {:ok, deleted}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Reorders landing sections by updating positions in a single transaction.

  Exempt from doctest — hits the database.
  """
  def reorder_landing_sections(scope, ordered_section_ids) do
    Marquee.Otel.with_span "marquee.landing_page.reorder_landing_sections",
                           %{"marquee.org.id" => scope.organization.id} do
      Repo.transaction(fn ->
        ordered_section_ids
        |> Enum.with_index()
        |> Enum.each(fn {id, position} ->
          LandingSection
          |> where(id: ^id, organization_id: ^scope.organization.id)
          |> Repo.update_all(set: [position: position])
        end)
      end)
      |> case do
        {:ok, _} ->
          Events.broadcast(scope, {:landing_sections_reordered, ordered_section_ids})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  ## -----------------------------------------------------------------------
  ## Resolution (read path that fans out to other contexts)
  ## -----------------------------------------------------------------------

  @doc """
  Resolves the dynamic content for a landing section.

  For `:content_row`, calls into the catalog/content modules to load the items.
  For `:plan_display`, loads the org's active plans.
  For `:hero_slider`, optionally loads the existing hero carousel slides.
  Other types are returned unchanged.

  Exempt from doctest — hits the database.
  """
  def resolve_landing_section(%Organization{} = organization, %LandingSection{} = section) do
    case section.section_type do
      :content_row ->
        items = resolve_content_row_items(organization, section.config)
        put_config(section, "items", items)

      :plan_display ->
        %{results: plans} = Billing.list_active_plans(organization, per_page: 100)
        put_config(section, "plans", plans)

      :hero_slider ->
        if section.config["use_existing_hero"] do
          %{slides: slides} = Catalog.resolve_hero_slides_cached(organization)
          put_config(section, "slides", slides)
        else
          section
        end

      _ ->
        section
    end
  end

  defp resolve_content_row_items(%Organization{} = organization, config) do
    source_type = config["source_type"]
    source_id = config["source_id"]
    max_items = config["max_items"] || 8

    case source_type do
      "collection" ->
        with {:ok, collection} <- Content.get_collection(organization, source_id),
             %{results: items} <-
               Content.list_collection_items(organization, collection, per_page: max_items) do
          items
        else
          _ -> []
        end

      "recent" ->
        %{results: videos} =
          Content.list_videos(organization,
            per_page: max_items,
            order_by: [desc: :inserted_at],
            exclude_episodes: true
          )

        videos

      _ ->
        []
    end
  end

  ## -----------------------------------------------------------------------
  ## Default seeding
  ## -----------------------------------------------------------------------

  @default_sections [
    %{
      section_type: :marketing_copy,
      config: %{
        "headline" => "Welcome",
        "body" => "Start streaming today.",
        "cta_text" => "Get started",
        "cta_link" => "/subscribe",
        "text_alignment" => "center"
      }
    },
    %{
      section_type: :header_text,
      config: %{
        "headline" => "What's inside",
        "size" => "large",
        "text_alignment" => "center"
      }
    },
    %{
      section_type: :content_row,
      config: %{
        "title" => "Featured",
        "source_type" => "recent",
        "max_items" => 8
      }
    },
    %{
      section_type: :plan_display,
      config: %{
        "headline" => "Choose your plan",
        "subheadline" => "Cancel anytime."
      }
    },
    %{
      section_type: :faq,
      config: %{
        "headline" => "Questions?",
        "items" => [
          %{
            "question" => "Can I cancel anytime?",
            "answer" => "Yes. Cancel at any time from your account page."
          },
          %{
            "question" => "What can I watch?",
            "answer" => "Your subscription gives you access to our full library."
          }
        ]
      }
    }
  ]

  @doc """
  Seeds a default landing page for an org. Inserts the default sections if the
  org has no existing landing sections. Tailors the hero headline to the org name.

  Exempt from doctest — hits the database.
  """
  def seed_default_landing_page(scope) do
    %Organization{} = org = scope.organization

    case list_landing_sections_admin(org) do
      %{results: []} ->
        @default_sections
        |> Enum.with_index()
        |> Enum.each(fn {section, index} ->
          attrs =
            section
            |> Map.put(:position, index)
            |> Map.put(:visible, true)
            |> personalize_default(org)

          {:ok, _} = create_landing_section(scope, attrs)
        end)

        :ok

      _ ->
        {:error, :already_seeded}
    end
  end

  defp personalize_default(%{section_type: :marketing_copy, config: config} = section, org) do
    Map.put(section, :config, Map.put(config, "headline", "Welcome to #{org.name}"))
  end

  defp personalize_default(section, _org), do: section

  ## -----------------------------------------------------------------------
  ## Helpers
  ## -----------------------------------------------------------------------

  defp put_config(%LandingSection{config: config} = section, key, value) do
    %{section | config: Map.put(config || %{}, key, value)}
  end

  defp ensure_position(%{"position" => p} = attrs, _org) when is_integer(p), do: attrs

  defp ensure_position(attrs, org) do
    Map.put(attrs, "position", next_position(org))
  end

  defp next_position(%Organization{id: org_id}) do
    LandingSection
    |> where(organization_id: ^org_id)
    |> where([s], is_nil(s.deleted_at))
    |> select([s], max(s.position))
    |> Repo.one()
    |> case do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  defp stringify_top_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      pair -> pair
    end)
  end
end
