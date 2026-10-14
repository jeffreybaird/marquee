defmodule MarqueeFeatures.Steps.TourTimer do
  @moduledoc """
  Navigation regression steps shared by the dashboard and page tour features.
  Only the next real hook mount's 400ms timer is held; LiveView performs the
  navigation and destruction. Releasing the timer honors actual clearTimeout
  calls, so a leaked callback runs on the destination and fails the scenario.
  """

  use Cucumberex.DSL
  use Wallaby.DSL
  import Wallaby.Query
  import MarqueeFeatures.Support.Browser, only: [visit_live: 2]

  when_("I leave the {string} page before its tour delay elapses", fn world, page ->
    {hook, source_path} =
      case page do
        "dashboard" -> {"GuidedTour", "/admin"}
        "content" -> {"PageTour", "/admin/content"}
      end

    session = visit_live(world.session, "/admin/collections?org=#{world.org.slug}")
    assert_has(session, css("[data-test=admin-nav-collections][aria-current=page]"))

    # A closure owns all instrumentation. No application global or hook state
    # is changed, and only scheduling inside this hook's real mounted() call
    # is intercepted. A real timeout handle retains clearTimeout semantics.
    session =
      execute_script(session, """
      const Hook = window.liveSocket.getHookDefinition(#{inspect(hook)});
      const mounted = Hook.prototype.mounted;
      const schedule = window.setTimeout;
      const clear = window.clearTimeout;
      const root = document.documentElement;
      let timer, callback, source, canceled = false;

      Hook.prototype.mounted = function() {
        Hook.prototype.mounted = mounted;
        source = this.el;
        window.setTimeout = function(fn, delay, ...args) {
          if (delay !== 400) return schedule(fn, delay, ...args);
          callback = () => fn(...args);
          timer = schedule(() => {}, 60000);
          root.setAttribute('data-tour-timer-held', #{inspect(hook)});
          return timer;
        };
        try { return mounted.call(this); }
        finally { window.setTimeout = schedule; }
      };

      window.clearTimeout = function(id) {
        if (id === timer) canceled = true;
        return clear(id);
      };

      document.addEventListener('pr03-release-tour-timer', () => {
        window.clearTimeout = clear;
        Hook.prototype.mounted = mounted;
        clear(timer);
        root.setAttribute('data-tour-source-removed', String(!source.isConnected));
        root.setAttribute('data-tour-timer-canceled', String(canceled));
        if (!canceled) callback();
        root.setAttribute('data-tour-timer-released', 'true');
      }, {once: true});
      """)

    session = click(session, css("#admin-sidebar a[href='#{source_path}']"))
    assert_has(session, css("html[data-tour-timer-held='#{hook}']"))
    assert_has(session, css("[phx-hook='#{hook}'][data-auto-start=true]", visible: :any))
    refute_has(session, css(".shepherd-element"))

    session = click(session, css("[data-test=admin-nav-collections]"))
    assert_has(session, css("[data-test=admin-nav-collections][aria-current=page]"))
    refute_has(session, css("[phx-hook='#{hook}']", visible: :any))

    Map.put(world, :session, session)
  end)

  then_("the departed page's pending tour is cleared without a lingering tour", fn world ->
    session =
      execute_script(world.session, """
      document.dispatchEvent(new Event('pr03-release-tour-timer'));
      """)

    assert_has(session, css("html[data-tour-source-removed=true]"))
    assert_has(session, css("html[data-tour-timer-released=true]"))
    assert_has(session, css("html[data-tour-timer-canceled=true]"))
    refute_has(session, css(".shepherd-element", visible: :any))
    refute_has(session, css(".shepherd-modal-overlay-container", visible: :any))
    world
  end)
end
