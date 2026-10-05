defmodule Marquee.PublishedDoctests do
  @moduledoc "Explicit registry for executing every published IEx example without filters."

  @pure_modules [
    Marquee.Accounts.AdminNudgeDismissal,
    Marquee.Accounts.Membership,
    Marquee.Accounts.Organization,
    Marquee.Accounts.PageTourCompletion,
    Marquee.Accounts.Scope,
    Marquee.Analytics.Snapshot,
    Marquee.Branding.Theme,
    Marquee.Catalog.Presets,
    Marquee.Catalog.Row,
    Marquee.Content.AccessControl,
    Marquee.Content.CollectionItem,
    Marquee.DemoSeeder,
    Marquee.Engagement.ContinueWatchingDismissal,
    Marquee.Engagement.PlaybackDropOff,
    Marquee.Features,
    Marquee.Idempotency,
    Marquee.LandingPage.LandingSection,
    Marquee.Pagination,
    Marquee.Podcasts.AccessControl,
    Marquee.Podcasts.FeedToken,
    Marquee.Podcasts.FeedXml,
    Marquee.Slug,
    Marquee.Streaming.ChatMessage,
    Marquee.Streaming.LiveEvent,
    Marquee.Streaming.LiveEventChatBan,
    Marquee.Streaming.LiveEventReminder,
    Marquee.Streaming.LiveEventTicket,
    Marquee.SubscriberDemo,
    Marquee.Viewers.SubscriptionAccess,
    Marquee.Viewers.Viewer,
    MarqueeWeb.Admin.CatalogLive.Components,
    MarqueeWeb.Admin.ContentLive.Components,
    MarqueeWeb.Admin.DashboardNudges,
    MarqueeWeb.Admin.OnboardingLive,
    MarqueeWeb.Components.DemoFeaturePreview,
    MarqueeWeb.Viewer.LiveEventController,
    MarqueeWeb.Viewer.WatchLive.Components,
    Mix.Tasks.Marquee.Verify
  ]

  @stateful_modules [
    Marquee.Accounts,
    Marquee.AdminDemo,
    Marquee.Billing,
    Marquee.Branding,
    Marquee.Catalog,
    Marquee.Content,
    Marquee.Engagement,
    Marquee.LandingPage,
    Marquee.Metrics,
    Marquee.Otel,
    Marquee.Otel.Export,
    Marquee.Otel.ExporterConfig,
    Marquee.Otel.Metrics,
    Marquee.PlatformBilling,
    Marquee.Podcasts.AudioProxy,
    Marquee.RequestContext,
    Marquee.Storage,
    Marquee.Storage.LocalClient,
    Marquee.Streaming,
    Marquee.Streaming.ChatRateLimiter,
    Marquee.Viewers,
    Marquee.Webhooks,
    MarqueeWeb.OrgURL,
    MarqueeWeb.Plugs.MemberPreview,
    MarqueeWeb.Plugs.RateLimit
  ]

  @doc "Returns explicit module registrations with the required isolated ExUnit case."
  def registrations do
    Enum.map(@pure_modules, &{&1, ExUnit.Case}) ++
      Enum.map(@stateful_modules, &{&1, Marquee.DataCase})
  end

  @doc "Lists compiled application modules containing published executable IEx examples."
  def documented_modules do
    :marquee
    |> Application.spec(:modules)
    |> Enum.filter(&published_examples?/1)
    |> Enum.sort()
  end

  @doc "Checks module documentation and authored entries, excluding only wholly generated dependency documentation."
  def authored_examples?(module_doc, entries) do
    # Ecto injects adapter reference documentation into Marquee.Repo. It
    # contains MySQL output and illustrative schemas, not application-owned
    # executable examples. Preserve all undocumented, mixed, or authored
    # provenance; a future authored Repo example must require registration.
    authored_docs =
      entries
      |> Enum.reject(fn {_, _, _, _, metadata} -> generated_entry?(metadata) end)
      |> Enum.map(fn {_, _, _, doc, _} -> doc end)

    Enum.any?([module_doc | authored_docs], &example_text?/1)
  end

  defp published_examples?(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, module_doc, _, entries} ->
        authored_examples?(module_doc, entries)

      {:error, :module_not_found} ->
        raise "Cannot inspect compiled documentation for #{inspect(module)}"

      {:error, :chunk_not_found} ->
        false
    end
  end

  defp generated_entry?(%{source_annos: [_ | _] = annotations}) do
    Enum.all?(annotations, &(is_list(&1) && Keyword.get(&1, :generated) == true))
  end

  defp generated_entry?(_), do: false

  defp example_text?(doc) when is_map(doc) do
    Enum.any?(Map.values(doc), &Regex.match?(~r/^\s*iex(?:\(\d+\))?>/m, &1))
  end

  defp example_text?(_), do: false
end
