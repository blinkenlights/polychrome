defmodule OctopusWeb.AppConfigComponent do
  use OctopusWeb, :live_component

  alias Octopus.AppSupervisor

  def mount(socket) do
    {:ok,
     assign(socket,
       config_info: nil,
       preset_save_name: "",
       preset_message: nil
     )}
  end

  def update(%{app_module: module} = assigns, socket) do
    config_schema = apply(module, :config_schema, [])
    config = Map.get(assigns, :config, AppSupervisor.config(assigns.app_id))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       config_schema: config_schema,
       config_schema_map: Map.new(config_schema),
       config: config,
       config_info: config_info(module, config)
     )
     |> assign_formula_preset_state(config, clear_message: false)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if Map.has_key?(assigns, :config) do
        assign_formula_preset_state(socket, assigns.config, clear_message: false)
      else
        socket
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <form class="space-y-4" phx-change="change" phx-target={@myself}>
        <div :for={{key, {name, type, opts}} <- visible_entries(@config_schema, @config)} class="form-control">
          <label :if={type != :button} class="label" for={"#{@app_id}-#{key}"}>
            <span class="label-text font-semibold">{name}</span>
          </label>
          <%= cond do %>
            <% type == :formula_preset -> %>
              <.formula_preset_input
                app_id={@app_id}
                key={key}
                value={@config[key]}
                opts={opts}
                target={@myself}
                presets={@formula_presets}
                selected_preset_id={@selected_preset_id}
                formula_valid={@formula_valid}
                preset_save_name={@preset_save_name}
                preset_message={@preset_message}
              />
            <% type in [:float, :int] -> %>
              <div class="flex items-center gap-2">
                <.config_input
                  class="flex-grow"
                  app_id={@app_id}
                  key={key}
                  name={name}
                  type={type}
                  opts={opts}
                  value={@config[key]}
                  target={@myself}
                />
                <.config_number
                  app_id={@app_id}
                  key={key}
                  type={type}
                  opts={opts}
                  value={@config[key]}
                />
              </div>
            <% true -> %>
              <.config_input
                class="w-full"
                app_id={@app_id}
                key={key}
                name={name}
                type={type}
                opts={opts}
                value={@config[key]}
                target={@myself}
              />
          <% end %>
        </div>
      </form>
      <p
        :if={@config_info}
        class="text-xs leading-snug opacity-70 mt-3 whitespace-pre-line"
      >
        {@config_info}
      </p>
    </div>
    """
  end

  def handle_event("config_action", %{"key" => key}, socket) do
    key = String.to_existing_atom(key)
    module = socket.assigns.app_module

    if function_exported?(module, :handle_config_action, 1) do
      module.handle_config_action(key)
    end

    {:noreply, socket}
  end

  def handle_event("change", params, socket) do
    case target_name(params["_target"]) do
      "program_preset_id" -> handle_preset_select(params, socket)
      "preset_save_name" -> {:noreply, assign(socket, preset_save_name: params["preset_save_name"] || "")}
      _ -> handle_config_change(params, socket)
    end
  end

  def handle_event("save_formula_preset", params, socket) do
    module = socket.assigns.formula_preset_module
    key = socket.assigns.formula_preset_key
    name = (params["preset_save_name"] || socket.assigns.preset_save_name || "") |> String.trim()
    formula = Map.get(socket.assigns.config, key, "")

    cond do
      is_nil(module) ->
        {:noreply, socket}

      name == "" ->
        {:noreply, assign(socket, preset_message: {:error, "Enter a preset name"})}

      module.validate_formula(formula) == :error ->
        {:noreply, assign(socket, preset_message: {:error, "Formula is invalid"})}

      true ->
        case module.create(%{name: name, formula: formula}) do
          {:ok, preset} ->
            {:noreply,
             socket
             |> assign(
               formula_presets: module.list_all(),
               selected_preset_id: preset.id,
               preset_save_name: "",
               preset_message: {:ok, "Preset saved"}
             )}

          {:error, changeset} ->
            {:noreply, assign(socket, preset_message: {:error, preset_error_message(changeset)})}
        end
    end
  end

  def handle_event("delete_formula_preset", _params, socket) do
    module = socket.assigns.formula_preset_module
    id = socket.assigns.selected_preset_id

    cond do
      is_nil(module) ->
        {:noreply, socket}

      not user_preset_id?(id) ->
        {:noreply, assign(socket, preset_message: {:error, "Only saved presets can be deleted"})}

      true ->
        case module.delete(id) do
          :ok ->
            {:noreply,
             socket
             |> assign(
               formula_presets: module.list_all(),
               selected_preset_id: "custom",
               preset_message: {:ok, "Preset deleted"}
             )}

          {:error, _} ->
            {:noreply, assign(socket, preset_message: {:error, "Could not delete preset"})}
        end
    end
  end

  defp handle_preset_select(%{"program_preset_id" => "custom"}, socket) do
    {:noreply, assign(socket, selected_preset_id: "custom", preset_message: nil)}
  end

  defp handle_preset_select(%{"program_preset_id" => preset_id}, socket) do
    module = socket.assigns.formula_preset_module
    key = socket.assigns.formula_preset_key

    case module.get(preset_id) do
      nil ->
        {:noreply, socket}

      %{formula: formula} ->
        new_config = Map.put(socket.assigns.config, key, formula)

        AppSupervisor.update_config(socket.assigns.app_id, new_config)

        {:noreply,
         socket
         |> assign(
           config: new_config,
           selected_preset_id: preset_id,
           formula_valid: true,
           preset_message: nil,
           config_info: config_info(socket.assigns.app_module, new_config)
         )}
    end
  end

  defp handle_config_change(params, socket) do
    changed_keys = target_keys(params)

    parsed =
      params
      |> Map.drop(["_target", "program_preset_id", "preset_save_name"])
      |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "_unused_") end)
      |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Enum.map(fn {key, value} ->
        {key, parse_option(key, value, socket.assigns.config_schema_map)}
      end)
      |> Map.new()

    config =
      changed_keys
      |> Enum.flat_map(fn key ->
        cond do
          Map.has_key?(parsed, key) ->
            [{key, Map.fetch!(parsed, key)}]

          boolean_field?(socket.assigns.config_schema_map, key) ->
            [{key, false}]

          true ->
            []
        end
      end)
      |> Map.new()

    new_config = Map.merge(socket.assigns.config, config)

    AppSupervisor.update_config(socket.assigns.app_id, new_config)

    {:noreply,
     socket
     |> assign(
       config: new_config,
       config_info: config_info(socket.assigns.app_module, new_config)
     )
     |> assign_formula_preset_state(new_config, clear_message: true)}
  end

  defp target_name(target) when is_binary(target), do: target
  defp target_name([target | _]), do: target
  defp target_name(_), do: nil

  defp target_keys(%{"_target" => target}) when is_list(target) do
    target |> Enum.flat_map(&schema_key/1)
  end

  defp target_keys(%{"_target" => target}) when is_binary(target) do
    schema_key(target)
  end

  defp target_keys(params) do
    params
    |> Map.drop(["_target", "program_preset_id", "preset_save_name"])
    |> Map.keys()
    |> Enum.flat_map(&schema_key/1)
  end

  defp schema_key(key) do
    [String.to_existing_atom(key)]
  rescue
    ArgumentError -> []
  end

  defp boolean_field?(schema, key) do
    case Map.get(schema, key) do
      {_name, :boolean, _opts} -> true
      _ -> false
    end
  end

  defp config_info(module, config) do
    if function_exported?(module, :config_info, 1) do
      module.config_info(config)
    end
  end

  defp visible_entries(config_schema, config) do
    Enum.filter(config_schema, fn {_key, {_name, _type, opts}} ->
      case Map.get(opts, :visible_when) do
        nil -> true
        {dep_key, allowed} -> Map.get(config, dep_key) in allowed
      end
    end)
  end

  defp assign_formula_preset_state(socket, config, opts) do
    clear_message? = Keyword.get(opts, :clear_message, false)

    case formula_preset_field(socket.assigns.config_schema) do
      nil ->
        socket
        |> assign(
          formula_presets: [],
          formula_preset_key: nil,
          formula_preset_module: nil,
          selected_preset_id: "custom",
          formula_valid: true
        )

      {key, _name, %{presets_module: module}} ->
        formula = Map.get(config, key, "")
        valid? = module.validate_formula(formula) == :ok

        socket
        |> assign(
          formula_presets: module.list_all(),
          formula_preset_key: key,
          formula_preset_module: module,
          selected_preset_id: module.id_for_formula(formula),
          formula_valid: valid?
        )
        |> then(fn s -> if clear_message?, do: assign(s, preset_message: nil), else: s end)
    end
  end

  defp formula_preset_field(config_schema) do
    Enum.find_value(config_schema, fn {key, {name, type, opts}} ->
      if type == :formula_preset, do: {key, name, opts}
    end)
  end

  defp user_preset_id?("user:" <> _), do: true
  defp user_preset_id?(_), do: false

  defp preset_error_message(changeset) do
    case changeset.errors do
      [{:name, {msg, _}} | _] -> "Name #{msg}"
      [{:formula, {msg, _}} | _] -> "Formula #{msg}"
      _ -> "Could not save preset"
    end
  end

  defp parse_option(key, value, config_schema) do
    type = config_schema |> Map.get(key) |> elem(1)

    case type do
      :float ->
        value |> Float.parse() |> elem(0)

      :int ->
        value |> Integer.parse() |> elem(0)

      :boolean ->
        value == "on"

      :select ->
        {_name, _type, %{options: options}} = Map.get(config_schema, key)
        i = value |> Integer.parse() |> elem(0)
        {_name, value} = Enum.at(options, i)
        value

      type when type in [:string, :formula_preset] ->
        value
    end
  end

  attr(:app_id, :string, required: true)
  attr(:key, :atom, required: true)
  attr(:type, :atom, required: true)
  attr(:name, :string, required: true)
  attr(:opts, :map, required: true)
  attr(:debounce, :integer, default: 100)
  attr(:value, :any, required: true)
  attr(:target, :any, default: nil)
  attr(:rest, :global)

  defp config_input(%{type: :float} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      step={@opts |> Map.get(:step, 0.01)}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      oninput={"if(this.nextElementSibling)this.nextElementSibling.value=this.value"}
      class="range range-primary range-sm"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :int} = assigns) do
    ~H"""
    <input
      type="range"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      step={@opts |> Map.get(:step, 1)}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      oninput={"if(this.nextElementSibling)this.nextElementSibling.value=this.value"}
      class="range range-primary range-sm"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :string} = assigns) do
    ~H"""
    <input
      type="text"
      name={@key}
      id={"#{@app_id}-#{@key}"}
      phx-debounce={@debounce}
      value={@value}
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
      id={"#{@app_id}-#{@key}"}
      phx-debounce={@debounce}
      checked={@value}
      class="checkbox checkbox-primary"
      {@rest}
    />
    """
  end

  defp config_input(%{type: :select} = assigns) do
    index =
      assigns.opts.options
      |> Enum.find_index(fn {_name, val} -> val == assigns.value end)
      |> case do
        nil -> 0
        i -> i
      end

    assigns = assign(assigns, :selected_index, index)

    ~H"""
    <select
      name={@key}
      id={"#{@app_id}-#{@key}"}
      phx-debounce={@debounce}
      class="select select-bordered w-full"
      value={@selected_index}
      {@rest}
    >
      <option
        :for={{{name, _value}, i} <- Enum.with_index(@opts.options)}
        value={i}
        selected={i == @selected_index}
      >
        {name}
      </option>
    </select>
    """
  end

  defp config_input(%{type: :button} = assigns) do
    ~H"""
    <button
      type="button"
      id={"#{@app_id}-#{@key}"}
      phx-click="config_action"
      phx-value-key={@key}
      phx-target={@target}
      class="btn btn-primary btn-sm w-full"
      {@rest}
    >
      {@name}
    </button>
    """
  end

  attr(:app_id, :string, required: true)
  attr(:key, :atom, required: true)
  attr(:value, :string, required: true)
  attr(:opts, :map, required: true)
  attr(:target, :any, required: true)
  attr(:presets, :list, required: true)
  attr(:selected_preset_id, :string, required: true)
  attr(:formula_valid, :boolean, required: true)
  attr(:preset_save_name, :string, default: "")
  attr(:preset_message, :any, default: nil)
  attr(:debounce, :integer, default: 100)

  defp formula_preset_input(assigns) do
    {builtin_presets, user_presets} =
      Enum.split_with(assigns.presets, & &1.builtin)

    assigns =
      assign(assigns,
        builtin_presets: builtin_presets,
        user_presets: user_presets,
        can_delete?: user_preset_id?(assigns.selected_preset_id),
        can_save?:
          assigns.formula_valid and String.trim(assigns.preset_save_name) != ""
      )

    ~H"""
    <div class="space-y-2">
      <label class="label py-0" for={"#{@app_id}-program-preset"}>
        <span class="label-text text-sm opacity-80">Preset</span>
      </label>
      <select
        name="program_preset_id"
        id={"#{@app_id}-program-preset"}
        phx-change="change"
        phx-target={@target}
        class="select select-bordered w-full"
      >
        <option value="custom" selected={@selected_preset_id == "custom"}>Custom</option>
        <optgroup label="Built-in">
          <option
            :for={preset <- @builtin_presets}
            value={preset.id}
            selected={preset.id == @selected_preset_id}
          >
            {preset.name}
          </option>
        </optgroup>
        <optgroup :if={@user_presets != []} label="Saved">
          <option
            :for={preset <- @user_presets}
            value={preset.id}
            selected={preset.id == @selected_preset_id}
          >
            {preset.name}
          </option>
        </optgroup>
      </select>

      <input
        type="text"
        name={@key}
        id={"#{@app_id}-#{@key}"}
        phx-debounce={@debounce}
        value={@value}
        class="input input-bordered w-full font-mono text-sm"
      />

      <p class={[
        "text-xs",
        @formula_valid && "text-success",
        !@formula_valid && "text-error"
      ]}>
        {if @formula_valid, do: "Valid formula", else: "Invalid formula syntax"}
      </p>

      <div class="flex flex-wrap items-end gap-2">
        <label class="form-control flex-grow min-w-[10rem]">
          <span class="label-text text-xs opacity-70">Save as</span>
          <input
            type="text"
            name="preset_save_name"
            id={"#{@app_id}-preset-save-name"}
            phx-debounce={@debounce}
            phx-change="change"
            phx-target={@target}
            value={@preset_save_name}
            placeholder="Preset name"
            class="input input-bordered input-sm w-full"
          />
        </label>
        <button
          type="button"
          id={"#{@app_id}-save-formula-preset"}
          phx-click="save_formula_preset"
          phx-target={@target}
          disabled={!@can_save?}
          class="btn btn-primary btn-sm"
        >
          Save preset
        </button>
        <button
          :if={@can_delete?}
          type="button"
          id={"#{@app_id}-delete-formula-preset"}
          phx-click="delete_formula_preset"
          phx-target={@target}
          class="btn btn-outline btn-error btn-sm"
        >
          Delete
        </button>
      </div>

      <p
        :if={@preset_message}
        class={[
          "text-xs",
          match?({:ok, _}, @preset_message) && "text-success",
          match?({:error, _}, @preset_message) && "text-error"
        ]}
      >
        {preset_message_text(@preset_message)}
      </p>
    </div>
    """
  end

  defp preset_message_text({:ok, message}), do: message
  defp preset_message_text({:error, message}), do: message

  attr(:app_id, :string, required: true)
  attr(:key, :atom, required: true)
  attr(:type, :atom, required: true)
  attr(:opts, :map, required: true)
  attr(:debounce, :integer, default: 100)
  attr(:value, :any, required: true)
  attr(:rest, :global)

  defp config_number(assigns) do
    ~H"""
    <input
      type="number"
      name={@key}
      id={"#{@app_id}-#{@key}-number"}
      step={@opts |> Map.get(:step, if(@type == :int, do: 1, else: 0.01))}
      min={@opts[:min]}
      max={@opts[:max]}
      phx-debounce={@debounce}
      value={@value}
      oninput={"if(this.previousElementSibling)this.previousElementSibling.value=this.value"}
      class="input input-bordered input-xs w-20 text-right tabular-nums shrink-0"
      {@rest}
    />
    """
  end
end
