defmodule Kraken.Define.SwitchTest do
  use ExUnit.Case

  alias Kraken.Test.Definitions
  alias Kraken.Define.Switch
  alias Kraken.Define.Pipeline

  @switch %{
    "type" => "switch",
    "name" => "my-switch",
    "branches" => %{
      "branch1" => [],
      "branch2" => []
    },
    # TODO it seems that the only way to use it is in "download" and "upload".
    "opts" => %{},
    "condition" => "if args['number'] <= 3, do: \"branch1\", else: \"branch2\""
  }

  test "define and call stage" do
    {:ok, switch_module} = Switch.define(@switch, Kraken.Pipelines.MyPipeline)
    assert switch_module == Kraken.Pipelines.MyPipeline.MySwitch

    assert "branch1" = apply(switch_module, :call, [%{"number" => 2}, %{}])
    assert "branch2" = apply(switch_module, :call, [%{"number" => 4}, %{}])

    assert_raise RuntimeError, "Event must be a map", fn ->
      apply(switch_module, :call, ["error", %{}])
    end
  end

  describe "simple pipeline with switch" do
    def define_and_start_service(name) do
      {:ok, ^name} =
        "services/#{name}.json"
        |> Definitions.read_and_decode()
        |> Octopus.define()

      {:ok, _code} = Octopus.start(name)
    end

    setup do
      define_and_start_service("simple-math")

      on_exit(fn ->
        Octopus.stop("simple-math")
        Octopus.delete("simple-math")
      end)
    end

    test "simple-math service" do
      assert {:ok, %{"sum" => 3}} = Octopus.call("simple-math", "add", %{"a" => 1, "b" => 2})
      assert {:ok, %{"result" => 10}} = Octopus.call("simple-math", "mult_by_two", %{"x" => 5})
      assert {:ok, %{"result" => 6}} = Octopus.call("simple-math", "add_one", %{"x" => 5})
    end

    @components [
      %{
        "type" => "stage",
        "name" => "add",
        "service" => %{
          "name" => "simple-math",
          "function" => "add"
        }
      },
      %{
        "type" => "switch",
        "name" => "my-switch",
        "branches" => %{
          "branch1" => [
            %{
              "type" => "stage",
              "name" => "mult",
              "service" => %{
                "name" => "simple-math",
                "function" => "mult_by_two"
              },
              "download" => %{
                "x" => "args['sum']"
              },
              "upload" => %{
                "x" => "args['result']"
              }
            }
          ],
          "branch2" => [
            %{
              "type" => "stage",
              "name" => "add-one",
              "service" => %{
                "name" => "simple-math",
                "function" => "add_one"
              },
              "download" => %{
                "x" => "args['sum']"
              },
              "upload" => %{
                "x" => "args['result']"
              }
            }
          ]
        },
        "condition" => "if args['sum'] <= 3, do: \"branch1\", else: \"branch2\""
      }
    ]

    @pipeline %{
      "name" => "SwitchPipeline",
      "components" => @components
    }

    test "define and call pipeline" do
      Pipeline.define(@pipeline)
      Kraken.Pipelines.SwitchPipeline.start()
      assert %{"x" => 6} = Kraken.Pipelines.SwitchPipeline.call(%{"a" => 1, "b" => 2})
      assert %{"x" => 5} = Kraken.Pipelines.SwitchPipeline.call(%{"a" => 2, "b" => 2})
    end
  end
end