defmodule Marquee.CIWorkflowTest do
  use ExUnit.Case, async: true

  @workflow ".github/workflows/ci.yml"

  @compile_step "run: mix compile --warnings-as-errors"
  @credo_step "run: mix credo --strict"
  @audit_step "run: mix deps.audit"
  @coveralls_step "run: mix coveralls --exclude e2e"
  @dialyzer_step "run: mix dialyzer"

  test "test job runs credo, deps.audit and dialyzer" do
    job = test_job()

    assert job =~ @credo_step
    assert job =~ @audit_step
    assert job =~ @dialyzer_step
  end

  test "test job orders compile, credo, deps.audit, coveralls then dialyzer" do
    job = test_job()

    positions =
      Enum.map(
        [@compile_step, @credo_step, @audit_step, @coveralls_step, @dialyzer_step],
        &step_position(job, &1)
      )

    assert positions == Enum.sort(positions)
    assert positions == Enum.uniq(positions)
  end

  test "test job keeps formatting and compile checks" do
    job = test_job()

    assert job =~ "run: mix format --check-formatted"
    assert job =~ @compile_step
  end

  defp test_job do
    workflow = File.read!(@workflow)
    [_before, rest] = String.split(workflow, "\n  test:\n", parts: 2)
    [job, _after] = String.split(rest, "\n  e2e:\n", parts: 2)
    job
  end

  defp step_position(job, step) do
    case :binary.match(job, step) do
      {position, _length} -> position
      :nomatch -> flunk("test job is missing step `#{step}`")
    end
  end
end
