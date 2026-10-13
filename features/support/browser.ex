defmodule MarqueeFeatures.Support.Browser do
  @moduledoc """
  Wallaby helpers shared by every step-definition module.

  `features/support/**` is compiled before `features/step_definitions/**`,
  so step modules can `import MarqueeFeatures.Support.Browser`.

  Two recurring sources of flaky Cucumber steps are handled here:

    * A `phx-click` / `phx-change` dispatched before the LiveView socket has
      joined is dropped silently by LiveView. `visit/2` only waits for the
      document to load, so steps must wait for `.phx-connected` on the root
      before interacting (`await_live_connect/1`, `visit_live/2`).

    * Wallaby's `set_value/3` on a `<select>` sends keystrokes, which Chrome
      matches against the visible option *text* — a typed option *value*
      (a UUID, an action slug) never selects anything and never fires
      `change`. Clicking the `<option>` itself does (`select_option/3`).
  """

  import Kernel, except: [tap: 2]
  import Wallaby.Browser
  import Wallaby.Query, only: [css: 1]

  @live_connected "[data-phx-main].phx-connected"

  @doc """
  Blocks until the page's root LiveView reports a joined socket.
  """
  def await_live_connect(session), do: assert_has(session, css(@live_connected))

  @doc """
  Visits `path` and waits for the root LiveView to connect.
  """
  def visit_live(session, path) do
    session
    |> visit(path)
    |> await_live_connect()
  end

  @doc """
  Selects the `<option>` whose `value` attribute equals `value` inside the
  `<select>` matched by `select_css`, firing the browser `change` event.
  """
  def select_option(session, select_css, value) do
    click(session, css("#{select_css} option[value='#{value}']"))
  end
end
