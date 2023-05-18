defmodule Kraken.Define.PlugTest do
  use ExUnit.Case

  alias Kraken.Test.Definitions
  alias Kraken.Define.Pipeline

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
    {:ok, result} = Octopus.call("simple-math", "add", %{"a" => 1, "b" => 2})
    assert result == %{"sum" => 3}
  end

  @components [
    %{
      "type" => "stage",
      "name" => "add",
      "service" => %{
        "name" => "simple-math",
        "function" => "add"
      },
      "download" => %{
        "a" => "args['x']",
        "b" => "args['y']"
      },
      "upload" => %{
        "z" => "args['sum']"
      }
    },
    %{
      "type" => "stage",
      "name" => "mult",
      "service" => %{
        "name" => "simple-math",
        "function" => "mult_by_two"
      },
      "download" => %{
        "x" => "args['z']"
      },
      "upload" => %{
        "z" => "args['result']"
      }
    }
  ]

  @pipeline %{
    "name" => "AddMultPipeline",
    "components" => @components
  }

  test "define and call pipeline" do
    Pipeline.define(@pipeline)
    apply(Kraken.Pipelines.AddMultPipeline, :start, [])

    result = apply(Kraken.Pipelines.AddMultPipeline, :call, [%{"x" => 1, "y" => 2}])
    assert result == %{"x" => 1, "y" => 2, "z" => 6}
  end

  describe "plug" do
    @plug %{
      "type" => "plug",
      "name" => "my-plug",
      "pipeline" => "AddMultPipeline",
      "download" => %{
        "x" => "args['xxx']",
        "y" => "args['yyy']"
      },
      "upload" => %{
        "zzz" => "args['z']"
      }
    }

    @extended_pipeline %{
      "name" => "ExtendedPipeline",
      "components" => [@plug]
    }

    test "plug module" do
      Pipeline.define(@pipeline)
      Pipeline.define(@extended_pipeline)
      plug_module = Kraken.Pipelines.ExtendedPipeline.MyPlug
      result = apply(plug_module, :plug, [%{"xxx" => 1, "yyy" => 2}, %{}])
      assert result == %{"x" => 1, "y" => 2}

      result = apply(plug_module, :unplug, [%{"z" => 3}, %{"xxx" => 1, "yyy" => 2}, %{}])
      assert result == %{"xxx" => 1, "yyy" => 2, "zzz" => 3}
    end

    test "define and call pipeline" do
      Pipeline.define(@pipeline)
      Pipeline.define(@extended_pipeline)
      apply(Kraken.Pipelines.ExtendedPipeline, :start, [])

      result = apply(Kraken.Pipelines.ExtendedPipeline, :call, [%{"xxx" => 1, "yyy" => 2}])
      assert result == %{"xxx" => 1, "yyy" => 2, "zzz" => 6}
    end
  end
end