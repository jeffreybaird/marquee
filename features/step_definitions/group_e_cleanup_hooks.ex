defmodule MarqueeFeatures.Steps.GroupECleanupHooks do
  @moduledoc """
  Scenario teardown for global state that viewer-management and audit-log
  steps switch on mid-scenario. A step that fails before its own cleanup
  would otherwise leak that state into later scenarios:

    * Mox global mode (CSV export stubs `Marquee.Storage.MockSpacesClient`)
    * Swoosh's `:shared_test_process` (magic-link and invitation capture)
    * a started `Marquee.Events.AuditSubscriber` (super-admin grant audit),
      which the test env never starts on its own
  """

  use Cucumberex.Hooks.DSL

  after_ fn world ->
    Mox.set_mox_private()
    Application.delete_env(:swoosh, :shared_test_process)
    stop_leftover_audit_subscriber()
    world
  end

  defp stop_leftover_audit_subscriber do
    case Process.whereis(Marquee.Events.AuditSubscriber) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  catch
    :exit, _already_stopped -> :ok
  end
end
