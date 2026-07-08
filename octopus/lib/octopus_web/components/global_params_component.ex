defmodule OctopusWeb.GlobalParamsComponent do
  use OctopusWeb, :live_component

  alias Octopus.Params.Global

  def update(assigns, socket) do
    config_schema = Global.config_schema()

    config =
      cond do
        Map.has_key?(assigns, :param_key) ->
          Map.put(current_config(socket), assigns.param_key, assigns.param_value)

        true ->
          current_config(socket)
      end

    assigns = Map.drop(assigns, [:param_key, :param_value])

    {:ok, socket |> assign(assigns) |> assign(config_schema: config_schema, config: config)}
  end

  defp current_config(%{assigns: %{config: config}}), do: config
  defp current_config(_), do: Global.config()

  def render(assigns) do
    ~H"""
    <div id="global-params-root">
      <form id="global-params-form" class="space-y-1.5" phx-change="change" phx-target={@myself}>
        <.compact_slider
          key={:speed}
          label="Speed"
          type={elem(@config_schema[:speed], 1)}
          opts={elem(@config_schema[:speed], 2)}
          value={@config[:speed]}
        />
        <.compact_slider
          key={:brightness}
          label="Bright"
          type={elem(@config_schema[:brightness], 1)}
          opts={elem(@config_schema[:brightness], 2)}
          value={@config[:brightness]}
          disabled={@config[:auto_brightness]}
          hint={@config[:auto_brightness] && "auto"}
        />
        <label class="flex items-center gap-1.5 cursor-pointer w-fit">
          <input
            type="checkbox"
            name="auto_brightness"
            id="global-auto_brightness"
            phx-debounce="100"
            checked={@config[:auto_brightness]}
            class="checkbox checkbox-primary checkbox-xs"
          />
          <span class="text-[11px] opacity-60">Auto brightness</span>
        </label>
      </form>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".GlobalParamSlider">
      function sliderToSpeed(slider, min, max, steps) {
        const t = Math.max(0, Math.min(steps, slider)) / steps
        const speed = min * Math.pow(max / min, t)
        return Math.max(min, Math.min(max, speed))
      }

      function formatSpeed(speed) {
        if (speed >= 10) return "10"
        if (speed >= 1) return trimZeros(speed.toFixed(2))
        if (speed >= 0.1) return trimZeros(speed.toFixed(2))
        return trimZeros(speed.toFixed(3))
      }

      function trimZeros(value) {
        return value.replace(/\.?0+$/, "")
      }

      function formatDisplay(el, raw) {
        const type = el.dataset.valueType

        if (type === "exp_float") {
          const min = parseFloat(el.dataset.speedMin)
          const max = parseFloat(el.dataset.speedMax)
          const steps = parseInt(el.dataset.speedSteps, 10)
          return formatSpeed(sliderToSpeed(raw, min, max, steps))
        }

        return String(raw)
      }

      export default {
        mounted() {
          this.input = this.el.querySelector('input[type="range"]')
          this.display = this.el.querySelector("[data-value-display]")
          this.onInput = () => {
            this.display.textContent = formatDisplay(this.el, Number(this.input.value))
          }
          this.input.addEventListener("input", this.onInput)
        },
        updated() {
          if (document.activeElement !== this.input) {
            this.display.textContent = formatDisplay(this.el, Number(this.input.value))
          }
        },
        destroyed() {
          this.input.removeEventListener("input", this.onInput)
        }
      }
    </script>
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

    {:noreply, assign(socket, config: Map.merge(socket.assigns.config, config))}
  end

  attr :key, :atom, required: true
  attr :label, :string, required: true
  attr :type, :atom, required: true
  attr :opts, :map, required: true
  attr :value, :any, required: true
  attr :disabled, :boolean, default: false
  attr :hint, :string, default: nil

  defp compact_slider(assigns) do
    ~H"""
    <div
      id={"global-slider-#{@key}"}
      phx-hook={if(is_nil(@hint), do: ".GlobalParamSlider")}
      data-value-type={@type}
      data-speed-min={Global.speed_min()}
      data-speed-max={Global.speed_max()}
      data-speed-steps={Global.speed_slider_steps()}
      class={["flex items-center gap-2", @disabled && "opacity-50"]}
    >
      <label class="text-[11px] uppercase tracking-wide opacity-60 w-11 shrink-0" for={"global-#{@key}"}>
        {@label}
      </label>
      <.config_input
        key={@key}
        type={@type}
        opts={@opts}
        value={@value}
        disabled={@disabled}
        class="range range-primary range-xs flex-1 min-w-0"
      />
      <span data-value-display class="text-[11px] tabular-nums opacity-70 w-9 text-right shrink-0">
        {@hint || format_value(@key, @value)}
      </span>
    </div>
    """
  end

  defp format_value(:speed, value), do: Global.format_speed(value)
  defp format_value(_key, value), do: value

  defp parse_option(key, value, config_schema) do
    {_name, type, _opts} = Map.get(config_schema, key)

    case type do
      :exp_float ->
        value |> Integer.parse() |> elem(0) |> Global.slider_to_speed()

      :float ->
        value |> Float.parse() |> elem(0)

      :int ->
        value |> Integer.parse() |> elem(0)

      :boolean ->
        value == "on" or value == "true"

      :string ->
        value
    end
  end

  defp ensure_boolean_params(config, config_schema) do
    boolean_keys =
      config_schema
      |> Enum.filter(fn {_key, {_name, type, _opts}} -> type == :boolean end)
      |> Enum.map(fn {key, _} -> key end)

    Enum.reduce(boolean_keys, config, fn key, acc ->
      Map.put_new(acc, key, false)
    end)
  end

  attr :key, :atom, required: true
  attr :type, :atom, required: true
  attr :name, :string, default: ""
  attr :opts, :map, required: true
  attr :value, :any, required: true
  attr :disabled, :boolean, default: false
  attr :rest, :global

  defp config_input(%{type: :exp_float} = assigns) do
    slider_value = Global.speed_to_slider(assigns.value)
    assigns = assign(assigns, :slider_value, slider_value)

    ~H"""
    <input
      type="range"
      name={@key}
      id={"global-#{@key}"}
      step="1"
      min="0"
      max={Global.speed_slider_steps()}
      value={@slider_value}
      disabled={@disabled}
      class="range range-primary"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :float} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"global-#{@key}"}
      step={@opts |> Map.get(:step, 0.01)}
      min={@opts[:min]}
      max={@opts[:max]}
      value={@value}
      disabled={@disabled}
      class="range range-primary"
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
      value={@value}
      disabled={@disabled}
      class="range range-primary"
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
      phx-debounce="100"
      value={@value}
      disabled={@disabled}
      class="input input-bordered w-full"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :boolean} = assigns) do
    ~H"""
    <input
      type="checkbox"
      name={@key}
      id={"global-#{@key}"}
      phx-debounce="100"
      checked={@value}
      disabled={@disabled}
      class="checkbox checkbox-primary"
      {@rest}
    />
    """
  end
end
