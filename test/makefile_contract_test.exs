defmodule BotArmyDashboardLiveview.MakefileContractTest do
  @moduledoc """
  A health check for the Makefile itself.

  `make test` in this repo ran nothing and exited 0 for as long as the repo
  existed. The Makefile defined no `test` rule, and a `test/` directory sits in
  the repo root, so make matched the DIRECTORY — it printed "Nothing to be done
  for 'test'" and reported success. Worse, once `push: test compile` exists, the
  same collision lets `make push` skip the suite and still push.

  These are regression tests for that class. They read the Makefile as text
  instead of shelling out to `make`, so they cannot be fooled by the very
  behaviour they guard against.
  """
  use ExUnit.Case, async: true

  @makefile "Makefile"

  # The targets this repo's workflow tells you to run. Each must be a rule of its
  # own: with a directory of the same name present, a name without a rule is a
  # green light for work that never happened.
  @promised ~w(compile test push git-push release publish-release)

  defp makefile, do: File.read!(@makefile)

  defp rule_names(text) do
    ~r/^([A-Za-z0-9_.%-]+):(?!=)/m
    |> Regex.scan(text)
    |> Enum.map(fn [_, name] -> name end)
    |> MapSet.new()
  end

  # Every word on the right-hand side of a rule line, which includes `.PHONY:`
  # (its "prerequisites" are the names it declares phony). Continuations are not
  # followed: a prerequisite split across lines is rare enough here that missing
  # it costs a check rather than a false alarm.
  defp prerequisites(text) do
    ~r/^([A-Za-z0-9_.%-]+):[ \t]+([^#\n]+)$/m
    |> Regex.scan(text)
    |> Enum.flat_map(fn [_, _target, deps] -> String.split(deps) end)
    |> MapSet.new()
  end

  defp directories do
    File.ls!()
    |> Enum.filter(&File.dir?/1)
    |> MapSet.new()
  end

  test "every target the workflow promises is a rule, not a directory" do
    names = rule_names(makefile())
    missing = Enum.reject(@promised, &MapSet.member?(names, &1))

    assert missing == [],
           """
           #{@makefile} has no rule for: #{Enum.join(missing, ", ")}

           If a directory of that name exists in the repo root, `make <name>` will
           match the directory, print "Nothing to be done", and exit 0.
           """

    assert File.dir?("test"),
           "test/ is gone - if the directory is gone, this guard is no longer the point; " <>
             "replace it with whatever now protects `make test` from being a no-op."
  end

  test "no prerequisite is silently satisfied by a directory" do
    text = makefile()

    offenders =
      text
      |> prerequisites()
      |> MapSet.difference(rule_names(text))
      |> MapSet.intersection(directories())
      |> Enum.sort()

    assert offenders == [],
           """
           These are prerequisites in #{@makefile} with no rule of their own, and a
           directory of the same name sits in the repo root. make will match the
           DIRECTORY, so the step is skipped and the build still reports success:

           #{Enum.map_join(offenders, "\n", &"  - #{&1}/  ->  add a `#{&1}:` rule")}
           """
  end

  test "there is a suite for the test target to run" do
    # The belt to the braces above: a `test:` rule pointing at an empty directory
    # is still nothing being tested.
    assert Path.wildcard("test/**/*_test.exs") != []
  end
end
