defmodule Octopus.Protobuf.EasingMode do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :LINEAR, 0
  field :EASE_IN_QUAD, 1
  field :EASE_OUT_QUAD, 2
  field :EASE_IN_OUT_QUAD, 3
  field :EASE_IN_CUBIC, 4
  field :EASE_OUT_CUBIC, 5
  field :EASE_IN_OUT_CUBIC, 6
  field :EASE_IN_QUART, 7
  field :EASE_OUT_QUART, 8
  field :EASE_IN_OUT_QUART, 9
  field :EASE_IN_QUINT, 10
  field :EASE_OUT_QUINT, 11
  field :EASE_IN_OUT_QUINT, 12
  field :EASE_IN_EXPO, 13
  field :EASE_OUT_EXPO, 14
  field :EASE_IN_OUT_EXPO, 15
end

defmodule Octopus.Protobuf.EventType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :BUTTON, 0
  field :DIRECTION, 1
end

defmodule Octopus.Protobuf.Packet do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  oneof :content, 0

  field :config, 1, type: Octopus.Protobuf.Config, oneof: 0
  field :frame, 2, type: Octopus.Protobuf.Frame, oneof: 0
end

defmodule Octopus.Protobuf.Config do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :luminance, 1, type: :uint32
  field :easing_interval_ms, 2, type: :uint32, json_name: "easingIntervalMs"
  field :easing_mode, 3, type: Octopus.Protobuf.EasingMode, json_name: "easingMode", enum: true
  field :show_test_frame, 4, type: :bool, json_name: "showTestFrame"
  field :config_phash, 5, type: :uint32, json_name: "configPhash"
  field :enable_calibration, 6, type: :bool, json_name: "enableCalibration"
end

defmodule Octopus.Protobuf.Frame do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :data, 1, type: :bytes, deprecated: false
  field :palette, 2, type: :bytes, deprecated: false
end

defmodule Octopus.Protobuf.InputEvent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :type, 1, type: Octopus.Protobuf.EventType, enum: true
  field :value, 2, type: :uint32
end

defmodule Octopus.Protobuf.ClientPacket do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  oneof :content, 0

  field :client_info, 1, type: Octopus.Protobuf.ClientInfo, json_name: "clientInfo", oneof: 0
  field :remote_log, 2, type: Octopus.Protobuf.RemoteLog, json_name: "remoteLog", oneof: 0
end

defmodule Octopus.Protobuf.ClientInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :hostname, 1, type: :string, deprecated: false
  field :build_time, 2, type: :string, json_name: "buildTime", deprecated: false
  field :panel_index, 3, type: :uint32, json_name: "panelIndex"
  field :fps, 4, type: :uint32
  field :config_phash, 5, type: :uint32, json_name: "configPhash"
end

defmodule Octopus.Protobuf.RemoteLog do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :message, 1, type: :string, deprecated: false
end