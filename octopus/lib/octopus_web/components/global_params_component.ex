defmodule OctopusWeb.GlobalParamsComponent do
  use OctopusWeb, :live_component

  alias Octopus.Params.Global

  def mount(socket) do
    if connected?(socket) do
      Global.subscribe()
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    config_schema = Global.config_schema()
    config = Global.config()
    {:ok, socket |> assign(assigns) |> assign(config_schema: config_schema, config: config)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <form class="flex flex-col gap-4" phx-change="change" phx-target={@myself}>
        <div :for={{key, {name, type, opts}} <- @config_schema}>
          <label class="font-semibold" for={"global-#{key}"} class="block">
            {name}
            <%= if key == :brightness && @config[:auto_brightness] do %>
              <span class="text-xs text-blue-600 font-normal">(Auto-controlled)</span>
            <% end %>
          </label>
          <div class="flex flex-row items-center gap-2">
            <.config_input
              class={[
                "flex-grow",
                if(key == :brightness && @config[:auto_brightness], do: "opacity-50", else: "")
              ]}
              key={key}
              name={name}
              type={type}
              opts={opts}
              value={@config[key]}
              disabled={key == :brightness && @config[:auto_brightness]}
            />
            <span class="text-sm text-gray-600 min-w-[3rem]">{@config[key]}</span>
          </div>
        </div>
      </form>
    </div>
    """
  end

  def handle_event("change", params, socket) do
    config =
      params
      |> Map.drop(["_target"])
      |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "_unused_") end)
      |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Enum.map(fn {key, value} ->
        {key, parse_option(key, value, socket.assigns.config_schema)}
      end)
      |> Map.new()
      |> ensure_boolean_params(socket.assigns.config_schema)

    Global.update_config(config)

    # Update the local config for immediate UI feedback
    {:noreply, socket |> assign(config: config)}
  end

  defp parse_option(key, value, config_schema) do
    {_name, type, _opts} = Map.get(config_schema, key)

    case type do
      :float ->
        value |> Float.parse() |> elem(0)

      :int ->
        value |> Integer.parse() |> elem(0)

      :boolean ->
        value == "on"

      :string ->
        value
    end
  end

  # Ensure all boolean parameters are present in config
  # Missing boolean params (unchecked checkboxes) should be set to false
  defp ensure_boolean_params(config, config_schema) do
    boolean_keys =
      config_schema
      |> Enum.filter(fn {_key, {_name, type, _opts}} -> type == :boolean end)
      |> Enum.map(fn {key, _} -> key end)

    Enum.reduce(boolean_keys, config, fn key, acc ->
      Map.put_new(acc, key, false)
    end)
  end

  attr(:key, :atom, required: true)
  attr(:type, :atom, required: true)
  attr(:name, :string, required: true)
  attr(:opts, :map, required: true)
  attr(:debounce, :integer, default: 100)
  attr(:value, :any, required: true)
  attr(:disabled, :boolean, default: false)
  attr(:rest, :global)

  defp config_input(%{type: :float} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"global-#{@key}"}
      step={@opts |> Map.get(:step, 0.01)}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      disabled={@disabled}
      {@rest}
    />
    """
  end

  defp config_input(%{type: :int} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"global-#{@key}"}
      step={@opts |> Map.get(:step, 1)}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      disabled={@disabled}
      {@rest}
    />
    """
  end

  defp config_input(%{type: :string} = assigns) do
    ~H"""
    <input
      type="text"
      name={@key}
      id={"global-#{@key}"}
      phx-debounce={@debounce}
      value={@value}
      disabled={@disabled}
      {@rest}
    />
    """
  end

  defp config_input(%{type: :boolean} = assigns) do
    ~H"""
    <div {@rest}>
      <input
        type="checkbox"
        name={@key}
        id={"global-#{@key}"}
        phx-debounce={@debounce}
        checked={@value}
        disabled={@disabled}
      />
    </div>
    """
  end
end
