defmodule Mixer.Protobuf.EasingMode do
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
end

defmodule Mixer.Protobuf.Packet do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  oneof :content, 0

  field :config, 1, type: Mixer.Protobuf.Config, oneof: 0
  field :frame, 2, type: Mixer.Protobuf.Frame, oneof: 0
end

defmodule Mixer.Protobuf.Config do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :on_r, 1, type: :uint32, json_name: "onR"
  field :on_g, 2, type: :uint32, json_name: "onG"
  field :on_b, 3, type: :uint32, json_name: "onB"
  field :on_w, 4, type: :uint32, json_name: "onW"
  field :off_r, 5, type: :uint32, json_name: "offR"
  field :off_g, 6, type: :uint32, json_name: "offG"
  field :off_b, 7, type: :uint32, json_name: "offB"
  field :off_w, 8, type: :uint32, json_name: "offW"
  field :easing_interval_ms, 9, type: :uint32, json_name: "easingIntervalMs"
  field :pixel_easing, 10, type: Mixer.Protobuf.EasingMode, json_name: "pixelEasing", enum: true

  field :brightness_easing, 11,
    type: Mixer.Protobuf.EasingMode,
    json_name: "brightnessEasing",
    enum: true

  field :test_frame, 12, type: :bool, json_name: "testFrame"
end

defmodule Mixer.Protobuf.Frame do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :data, 1, type: :bytes, deprecated: false
  field :maxval, 2, type: :uint32
end

defmodule Mixer.Protobuf.ResponsePacket do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  oneof :content, 0

  field :client_info, 1, type: Mixer.Protobuf.ClientInfo, json_name: "clientInfo", oneof: 0
  field :remote_log, 2, type: Mixer.Protobuf.RemoteLog, json_name: "remoteLog", oneof: 0
end

defmodule Mixer.Protobuf.ClientInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :hostname, 1, type: :string, deprecated: false
  field :build_time, 2, type: :string, json_name: "buildTime", deprecated: false
  field :panel_index, 3, type: :int32, json_name: "panelIndex"
end

defmodule Mixer.Protobuf.RemoteLog do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :message, 1, type: :string, deprecated: false
end