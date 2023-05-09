defmodule Octopus.App do
  @moduledoc """
  Behaviour and functions for creating apps. An app gets started and supervised by the AppSupervisor. It can emit frames with `send_frame/1` that will be forwarded to the mixer.

  Add `use Octopus.App` to your app module to create an app. It will be added automatically to the list of availabe apps.

  An app works very similar to a GenServer and supports usual callbacks. (`init/1`, `handle_call/3`, `handle_cast/2`, `handle_info/2`, `terminate/2`).

  See `Octopus.Apps.SampleApp` for an example.
  """

  alias Octopus.Protobuf.{Frame}
  alias Octopus.{Mixer, AppSupervisor}

  @doc """
  Human readable name of the app. It will be used in the UI and other places to identify the app.
  """
  @callback name() :: binary()

  defmacro __using__(_) do
    quote do
      @behaviour Octopus.App
      use GenServer
      import Octopus.App

      def start_link(init_args) do
        GenServer.start_link(__MODULE__, :ok, init_args)
      end
    end
  end

  @doc """
  Send a frame to the mixer.
  """
  def send_frame(%Frame{} = frame) do
    app_id = AppSupervisor.lookup_app_id(self())
    Mixer.handle_frame(app_id, frame)
  end
end
