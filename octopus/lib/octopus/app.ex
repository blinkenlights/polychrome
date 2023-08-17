defmodule Octopus.App do
  @moduledoc """
  Behaviour and functions for creating apps. An app gets started and supervised by the AppSupervisor. It can emit frames with `send_frame/1` that will be forwarded to the mixer.

  Add `use Octopus.App` to your app module to create an app. It will be added automatically to the list of availabe apps.

  An app works very similar to a GenServer and supports usual callbacks. (`init/1`, `handle_call/3`, `handle_cast/2`, `handle_info/2`, `terminate/2`).

  See `Octopus.Apps.SampleApp` for an example.

  ## Inputs
  An app can implement the `handle_input/2` callback to react to input events. It will receive an Octopus.Protobuf.InputEvent struct and the genserver state.

  """

  alias Octopus.Canvas

  alias Octopus.Protobuf.{
    Frame,
    WFrame,
    RGBFrame,
    AudioFrame,
    InputEvent,
    ControlEvent,
    SynthFrame,
    SoundToLightControlEvent
  }

  alias Octopus.{Mixer, AppSupervisor}

  @supported_frames [Frame, RGBFrame, WFrame, AudioFrame, SynthFrame]

  @doc """
  Human readable name of the app. It will be used in the UI and other places to identify the app.
  """
  @callback name() :: binary()

  @doc """
  Optional callback to return an icon that will be used in the UI.
  """
  @callback icon() :: Canvas.t() | nil

  @doc """
  Optional callback to handle input events. An app will only receive input events if it is selected as active in the mixer.
  """
  @callback handle_input(%InputEvent{} | %SoundToLightControlEvent{}, state :: any) ::
              {:noreply, state :: any}

  @type config_option ::
          {String.t(), :int, %{min: integer(), max: integer(), default: integer()}}
          | {String.t(), :float, %{min: float(), max: float(), default: float()}}
          | {String.t(), :string, %{default: String.t()}}
          | {String.t(), :boolean, %{default: boolean()}}
          | {String.t(), :select, %{default: non_neg_integer(), options: list({binary(), any()})}}

  @type config_schema :: %{optional(any()) => config_option()}

  @doc """
  Returns the config schema for the app. The schema is used to generate the UI for the app interface.
  """
  @callback config_schema() :: config_schema()

  @doc """
  Returns the current config for the app. This is used to initialize the app interface UI when it is started.
  """
  @callback get_config(state :: any()) :: map()

  @doc """
  Optional callback to handle config updates. The config is updated by the UI and sent to the app via the `update_config/1` function.
  """
  @callback handle_config(config :: any(), state :: any()) :: {:noreply, state :: any()}

  @callback handle_control_event(%ControlEvent{}, state :: any()) :: {:noreply, state :: any()}

  defmacro __using__(opts) do
    category = Keyword.get(opts, :category, :misc)

    quote do
      @behaviour Octopus.App
      use GenServer
      import Octopus.App

      def start_link({config, init_args}) do
        GenServer.start_link(__MODULE__, config, init_args)
      end

      def handle_info({:event, %InputEvent{} = input_event}, state) do
        handle_input(input_event, state)
      end

      def handle_info({:event, %SoundToLightControlEvent{} = input_event}, state) do
        handle_input(input_event, state)
      end

      def handle_info({:event, %ControlEvent{} = control_event}, state) do
        handle_control_event(control_event, state)
      end

      def handle_call(:get_config, _from, state) do
        {:reply, get_config(state), state}
      end

      def handle_call({:update_config, config}, _from, state) do
        app_id = AppSupervisor.lookup_app_id(self())
        {:noreply, state} = handle_config(config, state)

        {:reply, :ok, state}
      end

      def icon, do: nil

      def category(), do: unquote(category)

      def handle_input(_input_event, state) do
        {:noreply, state}
      end

      def handle_control_event(_event, state) do
        {:noreply, state}
      end

      def handle_config(config, state) do
        {:noreply, state}
      end

      def config_schema() do
        %{}
      end

      def get_config(state) do
        %{}
      end

      defoverridable icon: 0
      defoverridable handle_input: 2
      defoverridable handle_control_event: 2
      defoverridable config_schema: 0
      defoverridable handle_config: 2
      defoverridable get_config: 1
    end
  end

  def play_sample(sample_path, channel) do
    send_frame(%AudioFrame{uri: Path.join("file://", sample_path), channel: channel}, self())
  end

  @doc """
  Send a frame to the mixer.
  """
  def send_frame(%frame_type{} = frame) when frame_type in @supported_frames do
    send_frame(frame, self())
  end

  def send_frame(%frame_type{} = frame, pid) when frame_type in @supported_frames do
    app_id = AppSupervisor.lookup_app_id(pid)
    Mixer.handle_frame(app_id, frame)
  end

  def send_canvas(%Canvas{} = canvas) do
    app_id = AppSupervisor.lookup_app_id(self())
    Mixer.handle_canvas(app_id, canvas)
  end

  @spec default_config(config_schema()) :: map
  def default_config(config_schema) do
    config_schema
    |> Enum.map(fn
      {key, {_name, :select, %{default: default, options: options}}} ->
        {_name, value} = Enum.at(options, default)
        {key, value}

      {key, {_name, _type, options}} ->
        {key, Map.fetch!(options, :default)}
    end)
    |> Map.new()
  end

  def get_screen_count() do
    config = Application.get_env(:octopus, :installation)
    config[:screens]
  end
end
