defmodule Octopus.Params do
  @moduledoc """
  A module to store and retrieve parameters.

  Parameters are stored in an Agent and can be accessed using `put/3` and `get/3` which both take a prefix, a key.
  The `param/2` macro should be used to retrieve a parameter in an application. The macro will register the parameter
  and return the value from the Agent. The prefix is inferred from the module where the macro is used.

  ## Usage

  ```elixir
  defmodule MyModule do
    use Octopus.Params, prefix: :my_module

    def some_function do
      default = 42.0
      value = param(:some_key, default)
      IO.puts("The value is \#{value}")
    end
  end
  ```
  """

  use Agent

  import Ecto.Query, only: [from: 2]

  alias Octopus.Repo

  require Logger

  defmodule Schema do
    use Ecto.Schema
    import Ecto.Changeset

    schema "params" do
      field :params, :binary

      timestamps()
    end

    def changeset(params, attrs \\ %{}) do
      params
      |> cast(attrs, [:params])
      |> validate_required([:params])
    end
  end

  def persist do
    params = :erlang.term_to_binary(all())

    %Schema{}
    |> Schema.changeset(%{params: params})
    |> Repo.insert!()
  end

  def load_persisted_config(offset \\ 0) do
    query =
      from p in Schema,
        order_by: [desc: p.inserted_at],
        limit: 1,
        offset: ^offset

    Repo.all(query)
    |> Enum.map(&:erlang.binary_to_term(&1.params))
    |> List.first()
  end

  def start_link(_) do
    Agent.start_link(&initial_values/0, name: __MODULE__)
  end

  defmacro __using__(opts) do
    prefix = Keyword.fetch!(opts, :prefix)

    quote do
      import unquote(__MODULE__)

      @prefix unquote(prefix)

      Module.register_attribute(__MODULE__, :params, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :prefix, accumulate: false, persist: true)

      def __params__ do
        apply(__MODULE__, :__info__, [:attributes])
        |> Keyword.get_values(:params)
        |> List.flatten()
      end

      def __prefix__ do
        @prefix
      end
    end
  end

  def initial_values do
    {:ok, modules} = :application.get_key(:octopus, :modules)

    Code.ensure_all_loaded!(modules)

    modules
    |> Enum.filter(&function_exported?(&1, :__params__, 0))
    |> Enum.reduce(%{}, fn module, acc ->
      module.__params__()
      |> Enum.reduce(acc, fn {key, default}, acc ->
        Map.put(acc, {to_string(module.__prefix__()), to_string(key)}, default)
      end)
    end)
  end

  defmacro param(key, default) do
    Module.put_attribute(__CALLER__.module, :params, {key, default})

    quote do
      unquote(__MODULE__).get(@prefix, unquote(key), unquote(default))
    end
  end

  def put(prefix, key, value) do
    Agent.update(__MODULE__, fn map ->
      full_key = {to_string(prefix), to_string(key)}

      if Map.has_key?(map, full_key) do
        Logger.debug("Setting #{inspect(full_key)} to #{inspect(value)}")
        Map.put(map, full_key, value)
      else
        Logger.debug("Ignoring unknown key: #{inspect(full_key)}")
        map
      end
    end)
  end

  def get(prefix, key, default) do
    Agent.get(__MODULE__, &Map.get(&1, {to_string(prefix), to_string(key)}, default))
  end

  def all do
    Agent.get(__MODULE__, &Map.to_list(&1))
  end
end
