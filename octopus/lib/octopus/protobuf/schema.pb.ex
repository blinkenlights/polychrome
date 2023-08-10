defmodule Octopus.Protobuf.SynthWaveform do
  @moduledoc false

  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :SINE, 0
  field :SAW, 1
  field :SQUARE, 2
end

defmodule Octopus.Protobuf.SynthFilterType do
  @moduledoc false

  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :BANDPASS, 0
  field :HIGHPASS, 1
  field :LOWPASS, 2
end

defmodule Octopus.Protobuf.SynthEventType do
  @moduledoc false

  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :CONFIG, 0
  field :NOTE_ON, 1
  field :NOTE_OFF, 2
end

defmodule Octopus.Protobuf.InputType do
  @moduledoc false

  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

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
  field :BUTTON_A_1, 14
  field :BUTTON_B_1, 15
  field :BUTTON_A_2, 16
  field :BUTTON_B_2, 17
end

defmodule Octopus.Protobuf.ControlEventType do
  @moduledoc false

  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :APP_SELECTED, 0
  field :APP_DESELECTED, 1
  field :APP_STARTED, 2
  field :APP_STOPPED, 3
end

defmodule Octopus.Protobuf.EasingMode do
  @moduledoc false

  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

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

defmodule Octopus.Protobuf.Packet do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  oneof :content, 0

  field :frame, 2, type: Octopus.Protobuf.Frame, oneof: 0
  field :w_frame, 3, type: Octopus.Protobuf.WFrame, json_name: "wFrame", oneof: 0
  field :rgb_frame, 4, type: Octopus.Protobuf.RGBFrame, json_name: "rgbFrame", oneof: 0
  field :audio_frame, 5, type: Octopus.Protobuf.AudioFrame, json_name: "audioFrame", oneof: 0
  field :synth_frame, 10, type: Octopus.Protobuf.SynthFrame, json_name: "synthFrame", oneof: 0
  field :input_event, 6, type: Octopus.Protobuf.InputEvent, json_name: "inputEvent", oneof: 0

  field :control_event, 9,
    type: Octopus.Protobuf.ControlEvent,
    json_name: "controlEvent",
    oneof: 0

  field :firmware_config, 1,
    type: Octopus.Protobuf.FirmwareConfig,
    json_name: "firmwareConfig",
    oneof: 0

  field :rgb_frame_part1, 7, type: Octopus.Protobuf.RGBFrame, json_name: "rgbFramePart1", oneof: 0
  field :rgb_frame_part2, 8, type: Octopus.Protobuf.RGBFrame, json_name: "rgbFramePart2", oneof: 0
end

defmodule Octopus.Protobuf.Frame do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :data, 1, type: :bytes, deprecated: false
  field :palette, 2, type: :bytes, deprecated: false
  field :easing_interval, 3, type: :uint32, json_name: "easingInterval"
end

defmodule Octopus.Protobuf.WFrame do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :data, 1, type: :bytes, deprecated: false
  field :palette, 2, type: :bytes, deprecated: false
  field :easing_interval, 3, type: :uint32, json_name: "easingInterval"
end

defmodule Octopus.Protobuf.RGBFrame do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :data, 1, type: :bytes, deprecated: false
  field :easing_interval, 2, type: :uint32, json_name: "easingInterval"
end

defmodule Octopus.Protobuf.AudioFrame do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :uri, 1, type: :string
  field :channel, 2, type: :uint32
end

defmodule Octopus.Protobuf.SynthAdsrConfig do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :attack, 1, type: :float
  field :decay, 2, type: :float
  field :sustain, 3, type: :float
  field :release, 4, type: :float
end

defmodule Octopus.Protobuf.SynthReverbConfig do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :room_size, 1, type: :float, json_name: "roomSize"
  field :width, 2, type: :float
  field :damping, 3, type: :float
  field :freeze_mode, 4, type: :float, json_name: "freezeMode"
  field :wet_level, 5, type: :float, json_name: "wetLevel"
end

defmodule Octopus.Protobuf.SynthConfig do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :wave_form, 1, type: Octopus.Protobuf.SynthWaveform, json_name: "waveForm", enum: true
  field :gain, 2, type: :float
  field :adsr_config, 3, type: Octopus.Protobuf.SynthAdsrConfig, json_name: "adsrConfig"

  field :filter_adsr_config, 4,
    type: Octopus.Protobuf.SynthAdsrConfig,
    json_name: "filterAdsrConfig"

  field :filter_type, 5,
    type: Octopus.Protobuf.SynthFilterType,
    json_name: "filterType",
    enum: true

  field :cutoff, 6, type: :float
  field :resonance, 7, type: :float
  field :reverb_config, 8, type: Octopus.Protobuf.SynthReverbConfig, json_name: "reverbConfig"
end

defmodule Octopus.Protobuf.SynthFrame do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :event_type, 1, type: Octopus.Protobuf.SynthEventType, json_name: "eventType", enum: true
  field :channel, 2, type: :uint32
  field :note, 3, type: :uint32
  field :velocity, 4, type: :float
  field :duration_ms, 5, type: :float, json_name: "durationMs"
  field :config, 6, type: Octopus.Protobuf.SynthConfig
end

defmodule Octopus.Protobuf.InputEvent do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :type, 1, type: Octopus.Protobuf.InputType, enum: true
  field :value, 3, type: :int32
end

defmodule Octopus.Protobuf.ControlEvent do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :type, 1, type: Octopus.Protobuf.ControlEventType, enum: true
end

defmodule Octopus.Protobuf.FirmwareConfig do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :luminance, 1, type: :uint32
  field :easing_mode, 2, type: Octopus.Protobuf.EasingMode, json_name: "easingMode", enum: true
  field :show_test_frame, 3, type: :bool, json_name: "showTestFrame"
  field :config_phash, 4, type: :uint32, json_name: "configPhash"
  field :enable_calibration, 5, type: :bool, json_name: "enableCalibration"
end

defmodule Octopus.Protobuf.FirmwarePacket do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  oneof :content, 0

  field :firmware_info, 1,
    type: Octopus.Protobuf.FirmwareInfo,
    json_name: "firmwareInfo",
    oneof: 0

  field :remote_log, 2, type: Octopus.Protobuf.RemoteLog, json_name: "remoteLog", oneof: 0
end

defmodule Octopus.Protobuf.FirmwareInfo do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

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

defmodule Octopus.Protobuf.RemoteLog do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :message, 1, type: :string, deprecated: false
end