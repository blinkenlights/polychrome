defmodule Octopus.App do
  @moduledoc """
  Behaviour and functions for creating apps. An app gets started and supervised by the AppSupervisor. It can emit frames with `send_frame/1` that will be forwarded to the mixer.

  Add `use Octopus.App` to your app module to create an app. It will be added automatically to the list of availabe apps.

  An app works very similar to a GenServer and supports usual callbacks. (`init/1`, `handle_call/3`, `handle_cast/2`, `handle_info/2`, `terminate/2`).

  See `Octopus.Apps.SampleApp` for an example.

  ## Inputs
  An app can implement the `handle_input/2` callback to react to input events. It will receive an Octopus.Protobuf.InputEvent struct and the genserver state.

  """

  alias Octopus.Protobuf.{Frame, WFrame, RGBFrame, AudioFrame, InputEvent}
  alias Octopus.{Mixer, AppSupervisor}

  @supported_frames [Frame, RGBFrame, WFrame, AudioFrame]

  @doc """
  Human readable name of the app. It will be used in the UI and other places to identify the app.
  """
  @callback name() :: binary()

  @doc """
  Optional callback to handle input events. An app will only receive input events if it is selected as active in the mixer.
  """
  @callback handle_input(%InputEvent{}, state :: any) :: {:noreply, state :: any}

  @type config_option ::
          {String.t(), :int, %{min: integer(), max: integer(), default: integer()}}
          | {String.t(), :float, %{min: float(), max: float(), default: float()}}
          | {String.t(), :string, %{default: String.t()}}

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

  defmacro __using__(_) do
    quote do
      @behaviour Octopus.App
      use GenServer
      import Octopus.App

      def start_link(init_args) do
        GenServer.start_link(__MODULE__, :ok, init_args)
      end

      def handle_info({:input, %InputEvent{} = input_event}, state) do
        handle_input(input_event, state)
      end

      def handle_call(:get_config, _from, state) do
        {:reply, get_config(state), state}
      end

      def handle_call({:update_config, config}, _from, state) do
        app_id = AppSupervisor.lookup_app_id(self())
        {:noreply, state} = handle_config(config, state)

        {:reply, :ok, state}
      end

      def handle_input(_input_event, state) do
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

      defoverridable handle_input: 2
      defoverridable config_schema: 0
      defoverridable handle_config: 2
      defoverridable get_config: 1
    end
  end

  @doc """
  Send a frame to the mixer.
  """
  def send_frame(%frame_type{} = frame) when frame_type in @supported_frames do
    app_id = AppSupervisor.lookup_app_id(self())
    Mixer.handle_frame(app_id, frame)
  end

  @spec default_config(config_schema()) :: map
  def default_config(config_schema) do
    config_schema
    |> Enum.map(fn {key, {_name, _type, options}} ->
      {key, Map.fetch!(options, :default)}
    end)
    |> Map.new()
  end
end
