defmodule Bobine.LandingPage.LandingSection do
  @moduledoc """
  A configurable section on an org's marketing landing page.

  Each section has a `:section_type` (one of the values in `@section_types`)
  and a `:config` map whose shape depends on the type. The shape is validated
  by `changeset/2` based on the section type.

  Sections are ordered by `:position` and can be hidden via `:visible`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @section_types [
    :hero_video,
    :hero_image,
    :hero_slider,
    :marketing_copy,
    :content_row,
    :plan_display,
    :header_text,
    :faq
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "landing_sections" do
    belongs_to :organization, Bobine.Accounts.Organization

    field :section_type, Ecto.Enum, values: @section_types
    field :position, :integer, default: 0
    field :visible, :boolean, default: true
    field :config, :map, default: %{}
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid section types.

  ## Examples

      iex> :hero_video in Bobine.LandingPage.LandingSection.section_types()
      true

      iex> length(Bobine.LandingPage.LandingSection.section_types())
      8
  """
  def section_types, do: @section_types

  @doc false
  def changeset(section, attrs) do
    section
    |> cast(attrs, [:organization_id, :section_type, :position, :visible, :config])
    |> validate_required([:organization_id, :section_type])
    |> validate_inclusion(:section_type, @section_types)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> normalize_config()
    |> validate_config()
    |> foreign_key_constraint(:organization_id)
  end

  # Coerce config to a string-keyed map. JSON storage round-trips with string
  # keys, so we normalize on input to keep reads consistent.
  defp normalize_config(changeset) do
    case get_change(changeset, :config) do
      nil -> changeset
      config when is_map(config) -> put_change(changeset, :config, stringify_keys(config))
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(v) when is_map(v) and not is_struct(v), do: stringify_keys(v)
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v), do: v

  defp validate_config(changeset) do
    section_type = get_field(changeset, :section_type)
    config = get_field(changeset, :config) || %{}

    case validate_config_for(section_type, config) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :config, message)
    end
  end

  # Hero sections allow empty media so an operator can add a stub and fill in
  # the video/image via the editor. Headline is also optional at create time;
  # the renderer tolerates blanks.
  defp validate_config_for(:hero_video, _config), do: :ok
  defp validate_config_for(:hero_image, _config), do: :ok

  defp validate_config_for(:hero_slider, _config), do: :ok

  defp validate_config_for(:marketing_copy, config) do
    if blank?(config["headline"]) and blank?(config["body"]) do
      {:error, "must include headline or body"}
    else
      :ok
    end
  end

  defp validate_config_for(:content_row, config) do
    case config["source_type"] do
      "collection" ->
        if blank?(config["source_id"]),
          do: {:error, "collection source requires source_id"},
          else: :ok

      "recent" ->
        :ok

      _ ->
        {:error, "source_type must be \"collection\" or \"recent\""}
    end
  end

  defp validate_config_for(:plan_display, _config), do: :ok

  defp validate_config_for(:header_text, config) do
    if blank?(config["headline"]),
      do: {:error, "must include headline"},
      else: :ok
  end

  defp validate_config_for(:faq, config) do
    case config["items"] do
      nil ->
        {:error, "must include items list"}

      items when is_list(items) ->
        if Enum.all?(items, &valid_faq_item?/1),
          do: :ok,
          else: {:error, "each FAQ item must include question and answer"}

      _ ->
        {:error, "items must be a list"}
    end
  end

  defp validate_config_for(_type, _config), do: :ok

  defp valid_faq_item?(%{"question" => q, "answer" => a}) when is_binary(q) and is_binary(a),
    do: q != "" and a != ""

  defp valid_faq_item?(_), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false
end
