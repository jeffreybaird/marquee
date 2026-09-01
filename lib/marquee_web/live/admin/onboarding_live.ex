defmodule MarqueeWeb.Admin.OnboardingLive do
  @moduledoc """
  Full-screen setup wizard shown once to a new admin (owner/admin) right after
  they create their service. Four steps — welcome, pick a theme, add the first
  video, finish — each skippable. Completing or skipping stamps
  `onboarding_completed_at` on the org so the wizard never nags again.

  Route: /admin/onboarding
  """

  use MarqueeWeb, :live_view

  alias Marquee.Accounts
  alias Marquee.Branding
  alias Marquee.Branding.Theme

  @first_step 1
  @last_step 4

  @doc """
  Returns true when the wizard should intercept this operator: the org has not
  finished onboarding and the member is an owner or admin (the roles that set a
  service up). Viewers/editors and already-onboarded orgs are never gated.

  ## Examples

      iex> MarqueeWeb.Admin.OnboardingLive.pending?(nil, nil)
      false

      iex> org = %Marquee.Accounts.Organization{onboarding_completed_at: nil}
      iex> member = %Marquee.Accounts.Membership{role: :owner}
      iex> MarqueeWeb.Admin.OnboardingLive.pending?(org, member)
      true

      iex> org = %Marquee.Accounts.Organization{onboarding_completed_at: ~U[2026-09-01 00:00:00Z]}
      iex> member = %Marquee.Accounts.Membership{role: :owner}
      iex> MarqueeWeb.Admin.OnboardingLive.pending?(org, member)
      false

      iex> org = %Marquee.Accounts.Organization{onboarding_completed_at: nil}
      iex> member = %Marquee.Accounts.Membership{role: :editor}
      iex> MarqueeWeb.Admin.OnboardingLive.pending?(org, member)
      false

  """
  def pending?(%Marquee.Accounts.Organization{} = org, %Marquee.Accounts.Membership{role: role})
      when role in [:owner, :admin],
      do: not Accounts.onboarding_complete?(org)

  def pending?(_org, _member), do: false

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns[:organization]
    member = socket.assigns[:current_membership]

    if pending?(org, member) do
      {:ok,
       socket
       |> assign(:page_title, "Set up your service")
       |> assign(:step, @first_step)
       |> assign(:last_step, @last_step)
       |> assign(:theme_presets, Theme.presets())
       |> assign(:selected_preset, Theme.default_preset_key())}
    else
      # Already onboarded, or not an owner/admin — nothing to set up here.
      {:ok, push_navigate(socket, to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event("next", _params, socket) do
    {:noreply, assign(socket, :step, min(socket.assigns.step + 1, @last_step))}
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :step, max(socket.assigns.step - 1, @first_step))}
  end

  def handle_event("select_theme", %{"preset" => key}, socket) do
    case Branding.apply_theme_preset(
           socket.assigns.current_scope,
           socket.assigns.organization,
           key
         ) do
      {:ok, _theme} ->
        {:noreply, assign(socket, :selected_preset, key)}

      {:error, :invalid_preset} ->
        {:noreply, put_flash(socket, :error, "That theme isn't available.")}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't apply that theme. Please try again.")}
    end
  end

  def handle_event("finish", _params, socket), do: {:noreply, complete_and_leave(socket)}

  def handle_event("skip", _params, socket), do: {:noreply, complete_and_leave(socket)}

  defp complete_and_leave(socket) do
    case Accounts.complete_onboarding(socket.assigns.organization) do
      {:ok, _org} ->
        socket
        |> put_flash(:info, "You're all set — welcome to your dashboard.")
        |> push_navigate(to: ~p"/admin")

      {:error, :validation, _changeset} ->
        put_flash(socket, :error, "Something went wrong finishing setup. Please try again.")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} organization={@organization}>
      <main class="mx-auto flex min-h-[80vh] max-w-2xl flex-col justify-center px-4 py-10">
        <nav aria-label="Setup progress" class="mb-8">
          <ol class="flex items-center gap-2" data-test="onboarding-progress">
            <li
              :for={n <- 1..@last_step}
              class={[
                "h-1.5 flex-1 rounded-full",
                if(n <= @step, do: "bg-[var(--color-accent,#2563EB)]", else: "bg-base-300")
              ]}
              aria-current={if(n == @step, do: "step", else: "false")}
            >
              <span class="sr-only">Step {n} of {@last_step}</span>
            </li>
          </ol>
        </nav>

        <section
          class="rounded-2xl border border-base-300 bg-base-100 p-8 shadow-sm"
          data-test={"onboarding-step-#{@step}"}
          aria-labelledby="onboarding-heading"
        >
          {render_step(assigns)}
        </section>

        <div class="mt-6 flex items-center justify-between">
          <button
            :if={@step > 1}
            type="button"
            phx-click="back"
            class="btn btn-ghost"
            data-test="onboarding-back"
          >
            Back
          </button>
          <span :if={@step == 1}></span>

          <button
            type="button"
            phx-click="skip"
            class="btn btn-link text-base-content/60"
            data-test="onboarding-skip"
          >
            Skip setup
          </button>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp render_step(%{step: 1} = assigns) do
    ~H"""
    <h1 id="onboarding-heading" class="text-2xl font-semibold">
      Welcome to {@organization.name}
    </h1>
    <p class="mt-3 text-base-content/70">
      Let's get your streaming service ready. In a couple of steps you'll pick a
      look and add your first video. You can change anything later.
    </p>
    <div class="mt-8 flex justify-end">
      <button type="button" phx-click="next" class="btn btn-primary" data-test="onboarding-next">
        Get started
      </button>
    </div>
    """
  end

  defp render_step(%{step: 2} = assigns) do
    ~H"""
    <h1 id="onboarding-heading" class="text-2xl font-semibold">Choose a look</h1>
    <p class="mt-3 text-base-content/70">
      Pick a starting theme for your viewer site. You can fine-tune colors and
      fonts anytime under Appearance.
    </p>

    <fieldset class="mt-6">
      <legend class="sr-only">Theme presets</legend>
      <div class="grid gap-4 sm:grid-cols-2">
        <label
          :for={{key, preset} <- @theme_presets}
          class={[
            "flex cursor-pointer flex-col gap-3 rounded-xl border-2 p-4 transition",
            if(@selected_preset == key,
              do: "border-[var(--color-accent,#2563EB)]",
              else: "border-base-300 hover:border-base-content/30"
            )
          ]}
          data-test={"onboarding-theme-#{key}"}
        >
          <span class="flex items-center gap-3">
            <input
              type="radio"
              name="preset"
              value={key}
              checked={@selected_preset == key}
              phx-click="select_theme"
              phx-value-preset={key}
              class="radio radio-primary"
            />
            <span class="font-medium">{preset.label}</span>
          </span>
          <span class="flex gap-2" aria-hidden="true">
            <span
              class="h-8 w-8 rounded-full border border-base-300"
              style={"background:#{preset.background}"}
            >
            </span>
            <span
              class="h-8 w-8 rounded-full border border-base-300"
              style={"background:#{preset.brand_primary}"}
            >
            </span>
          </span>
          <span class="text-sm text-base-content/60">{preset.description}</span>
        </label>
      </div>
    </fieldset>

    <div class="mt-8 flex justify-end">
      <button type="button" phx-click="next" class="btn btn-primary" data-test="onboarding-next">
        Continue
      </button>
    </div>
    """
  end

  defp render_step(%{step: 3} = assigns) do
    ~H"""
    <h1 id="onboarding-heading" class="text-2xl font-semibold">Add your first video</h1>
    <p class="mt-3 text-base-content/70">
      Your trial includes up to 5 hours of video. Head to your content library to
      upload — it opens in a new tab so you can keep this checklist open.
    </p>
    <div class="mt-8 flex flex-wrap items-center justify-end gap-3">
      <.link
        href={~p"/admin/content"}
        target="_blank"
        rel="noopener"
        class="btn btn-outline"
        data-test="onboarding-upload-link"
      >
        Upload videos
      </.link>
      <button type="button" phx-click="next" class="btn btn-primary" data-test="onboarding-next">
        Continue
      </button>
    </div>
    """
  end

  defp render_step(%{step: 4} = assigns) do
    ~H"""
    <h1 id="onboarding-heading" class="text-2xl font-semibold">You're ready to go</h1>
    <p class="mt-3 text-base-content/70">
      That's the setup. From your dashboard you can add more videos, invite
      viewers, build your catalog, and set up plans whenever you're ready.
    </p>
    <div class="mt-8 flex justify-end">
      <button
        type="button"
        phx-click="finish"
        class="btn btn-primary"
        data-test="onboarding-finish"
      >
        Go to dashboard
      </button>
    </div>
    """
  end
end
