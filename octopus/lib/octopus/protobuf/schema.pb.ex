defmodule InputType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :BUTTON_1, 0
  field :BUTTON_2, 1
  field :BUTTON_3, 2
  field :BUTTON_4, 3
  field :BUTTON_5, 4
  field :BUTTON_6, 5
  field :BUTTON_7, 6
  field :BUTTON_8, 7
  field :BUTTON_9, 8
  field :BUTTON_10, 9
  field :AXIS_X_1, 10
  field :AXIS_Y_1, 11
  field :AXIS_X_2, 12
  field :AXIS_Y_2, 13
  field :BUTTON_1_A, 14
  field :BUTTON_1_B, 15
  field :BUTTON_2_A, 16
  field :BUTTON_2_B, 17
end

defmodule ControlEventType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :APP_SELECTED, 0
  field :APP_DESELECTED, 1
  field :APP_STARTED, 2
  field :APP_STOPPED, 3
end

defmodule EasingMode do
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

defmodule Packet do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  oneof :content, 0

  field :frame, 2, type: Frame, oneof: 0
  field :w_frame, 3, type: WFrame, json_name: "wFrame", oneof: 0
  field :rgb_frame, 4, type: RGBFrame, json_name: "rgbFrame", oneof: 0
  field :audio_frame, 5, type: AudioFrame, json_name: "audioFrame", oneof: 0
  field :input_event, 6, type: InputEvent, json_name: "inputEvent", oneof: 0
  field :control_event, 9, type: ControlEvent, json_name: "controlEvent", oneof: 0
  field :firmware_config, 1, type: FirmwareConfig, json_name: "firmwareConfig", oneof: 0
  field :rgb_frame_part1, 7, type: RGBFrame, json_name: "rgbFramePart1", oneof: 0
  field :rgb_frame_part2, 8, type: RGBFrame, json_name: "rgbFramePart2", oneof: 0
end

defmodule Frame do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :data, 1, type: :bytes, deprecated: false
  field :palette, 2, type: :bytes, deprecated: false
  field :easing_interval, 3, type: :uint32, json_name: "easingInterval"
end

defmodule WFrame do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :data, 1, type: :bytes, deprecated: false
  field :palette, 2, type: :bytes, deprecated: false
  field :easing_interval, 3, type: :uint32, json_name: "easingInterval"
end

defmodule RGBFrame do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :data, 1, type: :bytes, deprecated: false
  field :easing_interval, 2, type: :uint32, json_name: "easingInterval"
end

defmodule AudioFrame do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :uri, 1, type: :string
  field :channel, 2, type: :uint32
end

defmodule InputEvent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :type, 1, type: InputType, enum: true
  field :value, 3, type: :int32
end

defmodule ControlEvent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :type, 1, type: ControlEventType, enum: true
end

defmodule FirmwareConfig do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :luminance, 1, type: :uint32
  field :easing_mode, 2, type: EasingMode, json_name: "easingMode", enum: true
  field :show_test_frame, 3, type: :bool, json_name: "showTestFrame"
  field :config_phash, 4, type: :uint32, json_name: "configPhash"
  field :enable_calibration, 5, type: :bool, json_name: "enableCalibration"
end

defmodule FirmwarePacket do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  oneof :content, 0

  field :firmware_info, 1, type: FirmwareInfo, json_name: "firmwareInfo", oneof: 0
  field :remote_log, 2, type: RemoteLog, json_name: "remoteLog", oneof: 0
end

defmodule FirmwareInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :hostname, 1, type: :string, deprecated: false
  field :build_time, 2, type: :string, json_name: "buildTime", deprecated: false
  field :panel_index, 3, type: :uint32, json_name: "panelIndex"
  field :frames_per_second, 4, type: :uint32, json_name: "framesPerSecond"
  field :config_phash, 5, type: :uint32, json_name: "configPhash"
  field :mac, 6, type: :string, deprecated: false
  field :ipv4, 7, type: :string, deprecated: false
  field :ipv6_local, 8, type: :string, json_name: "ipv6Local", deprecated: false
  field :ipv6_global, 9, type: :string, json_name: "ipv6Global", deprecated: false
  field :packets_per_second, 10, type: :uint32, json_name: "packetsPerSecond"
  field :uptime, 11, type: :uint64
  field :heap_size, 12, type: :uint32, json_name: "heapSize"
  field :free_heap, 13, type: :uint32, json_name: "freeHeap"
end

defmodule RemoteLog do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto3

  field :message, 1, type: :string, deprecated: false
end