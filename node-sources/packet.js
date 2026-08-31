export const encodeInputType = {
  BUTTON_1: 0,
  BUTTON_2: 1,
  BUTTON_3: 2,
  BUTTON_4: 3,
  BUTTON_5: 4,
  BUTTON_6: 5,
  BUTTON_7: 6,
  BUTTON_8: 7,
  BUTTON_9: 8,
  BUTTON_10: 9,
  AXIS_X_1: 10,
  AXIS_Y_1: 11,
  AXIS_X_2: 12,
  AXIS_Y_2: 13,
};

export const decodeInputType = {
  0: "BUTTON_1",
  1: "BUTTON_2",
  2: "BUTTON_3",
  3: "BUTTON_4",
  4: "BUTTON_5",
  5: "BUTTON_6",
  6: "BUTTON_7",
  7: "BUTTON_8",
  8: "BUTTON_9",
  9: "BUTTON_10",
  10: "AXIS_X_1",
  11: "AXIS_Y_1",
  12: "AXIS_X_2",
  13: "AXIS_Y_2",
};

export const encodeEasingMode = {
  LINEAR: 0,
  EASE_IN_QUAD: 1,
  EASE_OUT_QUAD: 2,
  EASE_IN_OUT_QUAD: 3,
  EASE_IN_CUBIC: 4,
  EASE_OUT_CUBIC: 5,
  EASE_IN_OUT_CUBIC: 6,
  EASE_IN_QUART: 7,
  EASE_OUT_QUART: 8,
  EASE_IN_OUT_QUART: 9,
  EASE_IN_QUINT: 10,
  EASE_OUT_QUINT: 11,
  EASE_IN_OUT_QUINT: 12,
  EASE_IN_EXPO: 13,
  EASE_OUT_EXPO: 14,
  EASE_IN_OUT_EXPO: 15,
};

export const decodeEasingMode = {
  0: "LINEAR",
  1: "EASE_IN_QUAD",
  2: "EASE_OUT_QUAD",
  3: "EASE_IN_OUT_QUAD",
  4: "EASE_IN_CUBIC",
  5: "EASE_OUT_CUBIC",
  6: "EASE_IN_OUT_CUBIC",
  7: "EASE_IN_QUART",
  8: "EASE_OUT_QUART",
  9: "EASE_IN_OUT_QUART",
  10: "EASE_IN_QUINT",
  11: "EASE_OUT_QUINT",
  12: "EASE_IN_OUT_QUINT",
  13: "EASE_IN_EXPO",
  14: "EASE_OUT_EXPO",
  15: "EASE_IN_OUT_EXPO",
};

export function encodePacket(message) {
  let bb = popByteBuffer();
  _encodePacket(message, bb);
  return toUint8Array(bb);
}

function _encodePacket(message, bb) {
  // optional Frame frame = 2;
  let $frame = message.frame;
  if ($frame !== undefined) {
    writeVarint32(bb, 18);
    let nested = popByteBuffer();
    _encodeFrame($frame, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }

  // optional WFrame w_frame = 3;
  let $w_frame = message.w_frame;
  if ($w_frame !== undefined) {
    writeVarint32(bb, 26);
    let nested = popByteBuffer();
    _encodeWFrame($w_frame, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }

  // optional RGBFrame rgb_frame = 4;
  let $rgb_frame = message.rgb_frame;
  if ($rgb_frame !== undefined) {
    writeVarint32(bb, 34);
    let nested = popByteBuffer();
    _encodeRGBFrame($rgb_frame, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }

  // optional AudioFrame audio_frame = 5;
  let $audio_frame = message.audio_frame;
  if ($audio_frame !== undefined) {
    writeVarint32(bb, 42);
    let nested = popByteBuffer();
    _encodeAudioFrame($audio_frame, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }

  // optional InputEvent input_event = 6;
  let $input_event = message.input_event;
  if ($input_event !== undefined) {
    writeVarint32(bb, 50);
    let nested = popByteBuffer();
    _encodeInputEvent($input_event, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }

  // optional FirmwareConfig firmware_config = 1;
  let $firmware_config = message.firmware_config;
  if ($firmware_config !== undefined) {
    writeVarint32(bb, 10);
    let nested = popByteBuffer();
    _encodeFirmwareConfig($firmware_config, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }

  // optional RGBFrame rgb_frame_part1 = 7;
  let $rgb_frame_part1 = message.rgb_frame_part1;
  if ($rgb_frame_part1 !== undefined) {
    writeVarint32(bb, 58);
    let nested = popByteBuffer();
    _encodeRGBFrame($rgb_frame_part1, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }

  // optional RGBFrame rgb_frame_part2 = 8;
  let $rgb_frame_part2 = message.rgb_frame_part2;
  if ($rgb_frame_part2 !== undefined) {
    writeVarint32(bb, 66);
    let nested = popByteBuffer();
    _encodeRGBFrame($rgb_frame_part2, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }
}

export function decodePacket(binary) {
  return _decodePacket(wrapByteBuffer(binary));
}

function _decodePacket(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional Frame frame = 2;
      case 2: {
        let limit = pushTemporaryLength(bb);
        message.frame = _decodeFrame(bb);
        bb.limit = limit;
        break;
      }

      // optional WFrame w_frame = 3;
      case 3: {
        let limit = pushTemporaryLength(bb);
        message.w_frame = _decodeWFrame(bb);
        bb.limit = limit;
        break;
      }

      // optional RGBFrame rgb_frame = 4;
      case 4: {
        let limit = pushTemporaryLength(bb);
        message.rgb_frame = _decodeRGBFrame(bb);
        bb.limit = limit;
        break;
      }

      // optional AudioFrame audio_frame = 5;
      case 5: {
        let limit = pushTemporaryLength(bb);
        message.audio_frame = _decodeAudioFrame(bb);
        bb.limit = limit;
        break;
      }

      // optional InputEvent input_event = 6;
      case 6: {
        let limit = pushTemporaryLength(bb);
        message.input_event = _decodeInputEvent(bb);
        bb.limit = limit;
        break;
      }

      // optional FirmwareConfig firmware_config = 1;
      case 1: {
        let limit = pushTemporaryLength(bb);
        message.firmware_config = _decodeFirmwareConfig(bb);
        bb.limit = limit;
        break;
      }

      // optional RGBFrame rgb_frame_part1 = 7;
      case 7: {
        let limit = pushTemporaryLength(bb);
        message.rgb_frame_part1 = _decodeRGBFrame(bb);
        bb.limit = limit;
        break;
      }

      // optional RGBFrame rgb_frame_part2 = 8;
      case 8: {
        let limit = pushTemporaryLength(bb);
        message.rgb_frame_part2 = _decodeRGBFrame(bb);
        bb.limit = limit;
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

export function encodeFrame(message) {
  let bb = popByteBuffer();
  _encodeFrame(message, bb);
  return toUint8Array(bb);
}

function _encodeFrame(message, bb) {
  // optional bytes data = 1;
  let $data = message.data;
  if ($data !== undefined) {
    writeVarint32(bb, 10);
    writeVarint32(bb, $data.length), writeBytes(bb, $data);
  }

  // optional bytes palette = 2;
  let $palette = message.palette;
  if ($palette !== undefined) {
    writeVarint32(bb, 18);
    writeVarint32(bb, $palette.length), writeBytes(bb, $palette);
  }

  // optional uint32 easing_interval = 3;
  let $easing_interval = message.easing_interval;
  if ($easing_interval !== undefined) {
    writeVarint32(bb, 24);
    writeVarint32(bb, $easing_interval);
  }
}

export function decodeFrame(binary) {
  return _decodeFrame(wrapByteBuffer(binary));
}

function _decodeFrame(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional bytes data = 1;
      case 1: {
        message.data = readBytes(bb, readVarint32(bb));
        break;
      }

      // optional bytes palette = 2;
      case 2: {
        message.palette = readBytes(bb, readVarint32(bb));
        break;
      }

      // optional uint32 easing_interval = 3;
      case 3: {
        message.easing_interval = readVarint32(bb) >>> 0;
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

export function encodeWFrame(message) {
  let bb = popByteBuffer();
  _encodeWFrame(message, bb);
  return toUint8Array(bb);
}

function _encodeWFrame(message, bb) {
  // optional bytes data = 1;
  let $data = message.data;
  if ($data !== undefined) {
    writeVarint32(bb, 10);
    writeVarint32(bb, $data.length), writeBytes(bb, $data);
  }

  // optional bytes palette = 2;
  let $palette = message.palette;
  if ($palette !== undefined) {
    writeVarint32(bb, 18);
    writeVarint32(bb, $palette.length), writeBytes(bb, $palette);
  }

  // optional uint32 easing_interval = 3;
  let $easing_interval = message.easing_interval;
  if ($easing_interval !== undefined) {
    writeVarint32(bb, 24);
    writeVarint32(bb, $easing_interval);
  }
}

export function decodeWFrame(binary) {
  return _decodeWFrame(wrapByteBuffer(binary));
}

function _decodeWFrame(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional bytes data = 1;
      case 1: {
        message.data = readBytes(bb, readVarint32(bb));
        break;
      }

      // optional bytes palette = 2;
      case 2: {
        message.palette = readBytes(bb, readVarint32(bb));
        break;
      }

      // optional uint32 easing_interval = 3;
      case 3: {
        message.easing_interval = readVarint32(bb) >>> 0;
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

export function encodeRGBFrame(message) {
  let bb = popByteBuffer();
  _encodeRGBFrame(message, bb);
  return toUint8Array(bb);
}

function _encodeRGBFrame(message, bb) {
  // optional bytes data = 1;
  let $data = message.data;
  if ($data !== undefined) {
    writeVarint32(bb, 10);
    writeVarint32(bb, $data.length), writeBytes(bb, $data);
  }

  // optional uint32 easing_interval = 2;
  let $easing_interval = message.easing_interval;
  if ($easing_interval !== undefined) {
    writeVarint32(bb, 16);
    writeVarint32(bb, $easing_interval);
  }
}

export function decodeRGBFrame(binary) {
  return _decodeRGBFrame(wrapByteBuffer(binary));
}

function _decodeRGBFrame(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional bytes data = 1;
      case 1: {
        message.data = readBytes(bb, readVarint32(bb));
        break;
      }

      // optional uint32 easing_interval = 2;
      case 2: {
        message.easing_interval = readVarint32(bb) >>> 0;
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

export function encodeAudioFrame(message) {
  let bb = popByteBuffer();
  _encodeAudioFrame(message, bb);
  return toUint8Array(bb);
}

function _encodeAudioFrame(message, bb) {
  // optional string uri = 1;
  let $uri = message.uri;
  if ($uri !== undefined) {
    writeVarint32(bb, 10);
    writeString(bb, $uri);
  }

  // optional uint32 channel = 2;
  let $channel = message.channel;
  if ($channel !== undefined) {
    writeVarint32(bb, 16);
    writeVarint32(bb, $channel);
  }
}

export function decodeAudioFrame(binary) {
  return _decodeAudioFrame(wrapByteBuffer(binary));
}

function _decodeAudioFrame(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional string uri = 1;
      case 1: {
        message.uri = readString(bb, readVarint32(bb));
        break;
      }

      // optional uint32 channel = 2;
      case 2: {
        message.channel = readVarint32(bb) >>> 0;
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

export function encodeInputEvent(message) {
  let bb = popByteBuffer();
  _encodeInputEvent(message, bb);
  return toUint8Array(bb);
}

function _encodeInputEvent(message, bb) {
  // optional InputType type = 1;
  let $type = message.type;
  if ($type !== undefined) {
    writeVarint32(bb, 8);
    writeVarint32(bb, encodeInputType[$type]);
  }

  // optional int32 value = 3;
  let $value = message.value;
  if ($value !== undefined) {
    writeVarint32(bb, 24);
    writeVarint64(bb, intToLong($value));
  }
}

export function decodeInputEvent(binary) {
  return _decodeInputEvent(wrapByteBuffer(binary));
}

function _decodeInputEvent(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional InputType type = 1;
      case 1: {
        message.type = decodeInputType[readVarint32(bb)];
        break;
      }

      // optional int32 value = 3;
      case 3: {
        message.value = readVarint32(bb);
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

export function encodeFirmwareConfig(message) {
  let bb = popByteBuffer();
  _encodeFirmwareConfig(message, bb);
  return toUint8Array(bb);
}

function _encodeFirmwareConfig(message, bb) {
  // optional uint32 luminance = 1;
  let $luminance = message.luminance;
  if ($luminance !== undefined) {
    writeVarint32(bb, 8);
    writeVarint32(bb, $luminance);
  }

  // optional EasingMode easing_mode = 2;
  let $easing_mode = message.easing_mode;
  if ($easing_mode !== undefined) {
    writeVarint32(bb, 16);
    writeVarint32(bb, encodeEasingMode[$easing_mode]);
  }

  // optional bool show_test_frame = 3;
  let $show_test_frame = message.show_test_frame;
  if ($show_test_frame !== undefined) {
    writeVarint32(bb, 24);
    writeByte(bb, $show_test_frame ? 1 : 0);
  }

  // optional uint32 config_phash = 4;
  let $config_phash = message.config_phash;
  if ($config_phash !== undefined) {
    writeVarint32(bb, 32);
    writeVarint32(bb, $config_phash);
  }

  // optional bool enable_calibration = 5;
  let $enable_calibration = message.enable_calibration;
  if ($enable_calibration !== undefined) {
    writeVarint32(bb, 40);
    writeByte(bb, $enable_calibration ? 1 : 0);
  }
}

export function decodeFirmwareConfig(binary) {
  return _decodeFirmwareConfig(wrapByteBuffer(binary));
}

function _decodeFirmwareConfig(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional uint32 luminance = 1;
      case 1: {
        message.luminance = readVarint32(bb) >>> 0;
        break;
      }

      // optional EasingMode easing_mode = 2;
      case 2: {
        message.easing_mode = decodeEasingMode[readVarint32(bb)];
        break;
      }

      // optional bool show_test_frame = 3;
      case 3: {
        message.show_test_frame = !!readByte(bb);
        break;
      }

      // optional uint32 config_phash = 4;
      case 4: {
        message.config_phash = readVarint32(bb) >>> 0;
        break;
      }

      // optional bool enable_calibration = 5;
      case 5: {
        message.enable_calibration = !!readByte(bb);
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

export function encodeFirmwarePacket(message) {
  let bb = popByteBuffer();
  _encodeFirmwarePacket(message, bb);
  return toUint8Array(bb);
}

function _encodeFirmwarePacket(message, bb) {
  // optional FirmwareInfo firmware_info = 1;
  let $firmware_info = message.firmware_info;
  if ($firmware_info !== undefined) {
    writeVarint32(bb, 10);
    let nested = popByteBuffer();
    _encodeFirmwareInfo($firmware_info, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }

  // optional RemoteLog remote_log = 2;
  let $remote_log = message.remote_log;
  if ($remote_log !== undefined) {
    writeVarint32(bb, 18);
    let nested = popByteBuffer();
    _encodeRemoteLog($remote_log, nested);
    writeVarint32(bb, nested.limit);
    writeByteBuffer(bb, nested);
    pushByteBuffer(nested);
  }
}

export function decodeFirmwarePacket(binary) {
  return _decodeFirmwarePacket(wrapByteBuffer(binary));
}

function _decodeFirmwarePacket(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional FirmwareInfo firmware_info = 1;
      case 1: {
        let limit = pushTemporaryLength(bb);
        message.firmware_info = _decodeFirmwareInfo(bb);
        bb.limit = limit;
        break;
      }

      // optional RemoteLog remote_log = 2;
      case 2: {
        let limit = pushTemporaryLength(bb);
        message.remote_log = _decodeRemoteLog(bb);
        bb.limit = limit;
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

export function encodeFirmwareInfo(message) {
  let bb = popByteBuffer();
  _encodeFirmwareInfo(message, bb);
  return toUint8Array(bb);
}

function _encodeFirmwareInfo(message, bb) {
  // optional string hostname = 1;
  let $hostname = message.hostname;
  if ($hostname !== undefined) {
    writeVarint32(bb, 10);
    writeString(bb, $hostname);
  }

  // optional string build_time = 2;
  let $build_time = message.build_time;
  if ($build_time !== undefined) {
    writeVarint32(bb, 18);
    writeString(bb, $build_time);
  }

  // optional uint32 panel_index = 3;
  let $panel_index = message.panel_index;
  if ($panel_index !== undefined) {
    writeVarint32(bb, 24);
    writeVarint32(bb, $panel_index);
  }

  // optional uint32 fps = 4;
  let $fps = message.fps;
  if ($fps !== undefined) {
    writeVarint32(bb, 32);
    writeVarint32(bb, $fps);
  }

  // optional uint32 config_phash = 5;
  let $config_phash = message.config_phash;
  if ($config_phash !== undefined) {
    writeVarint32(bb, 40);
    writeVarint32(bb, $config_phash);
  }
}

export function decodeFirmwareInfo(binary) {
  return _decodeFirmwareInfo(wrapByteBuffer(binary));
}

function _decodeFirmwareInfo(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional string hostname = 1;
      case 1: {
        message.hostname = readString(bb, readVarint32(bb));
        break;
      }

      // optional string build_time = 2;
      case 2: {
        message.build_time = readString(bb, readVarint32(bb));
        break;
      }

      // optional uint32 panel_index = 3;
      case 3: {
        message.panel_index = readVarint32(bb) >>> 0;
        break;
      }

      // optional uint32 fps = 4;
      case 4: {
        message.fps = readVarint32(bb) >>> 0;
        break;
      }

      // optional uint32 config_phash = 5;
      case 5: {
        message.config_phash = readVarint32(bb) >>> 0;
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

export function encodeRemoteLog(message) {
  let bb = popByteBuffer();
  _encodeRemoteLog(message, bb);
  return toUint8Array(bb);
}

function _encodeRemoteLog(message, bb) {
  // optional string message = 1;
  let $message = message.message;
  if ($message !== undefined) {
    writeVarint32(bb, 10);
    writeString(bb, $message);
  }
}

export function decodeRemoteLog(binary) {
  return _decodeRemoteLog(wrapByteBuffer(binary));
}

function _decodeRemoteLog(bb) {
  let message = {};

  end_of_message: while (!isAtEnd(bb)) {
    let tag = readVarint32(bb);

    switch (tag >>> 3) {
      case 0:
        break end_of_message;

      // optional string message = 1;
      case 1: {
        message.message = readString(bb, readVarint32(bb));
        break;
      }

      default:
        skipUnknownField(bb, tag & 7);
    }
  }

  return message;
}

function pushTemporaryLength(bb) {
  let length = readVarint32(bb);
  let limit = bb.limit;
  bb.limit = bb.offset + length;
  return limit;
}

function skipUnknownField(bb, type) {
  switch (type) {
    case 0: while (readByte(bb) & 0x80) { } break;
    case 2: skip(bb, readVarint32(bb)); break;
    case 5: skip(bb, 4); break;
    case 1: skip(bb, 8); break;
    default: throw new Error("Unimplemented type: " + type);
  }
}

function stringToLong(value) {
  return {
    low: value.charCodeAt(0) | (value.charCodeAt(1) << 16),
    high: value.charCodeAt(2) | (value.charCodeAt(3) << 16),
    unsigned: false,
  };
}

function longToString(value) {
  let low = value.low;
  let high = value.high;
  return String.fromCharCode(
    low & 0xFFFF,
    low >>> 16,
    high & 0xFFFF,
    high >>> 16);
}

// The code below was modified from https://github.com/protobufjs/bytebuffer.js
// which is under the Apache License 2.0.

let f32 = new Float32Array(1);
let f32_u8 = new Uint8Array(f32.buffer);

let f64 = new Float64Array(1);
let f64_u8 = new Uint8Array(f64.buffer);

function intToLong(value) {
  value |= 0;
  return {
    low: value,
    high: value >> 31,
    unsigned: value >= 0,
  };
}

let bbStack = [];

function popByteBuffer() {
  const bb = bbStack.pop();
  if (!bb) return { bytes: new Uint8Array(64), offset: 0, limit: 0 };
  bb.offset = bb.limit = 0;
  return bb;
}

function pushByteBuffer(bb) {
  bbStack.push(bb);
}

function wrapByteBuffer(bytes) {
  return { bytes, offset: 0, limit: bytes.length };
}

function toUint8Array(bb) {
  let bytes = bb.bytes;
  let limit = bb.limit;
  return bytes.length === limit ? bytes : bytes.subarray(0, limit);
}

function skip(bb, offset) {
  if (bb.offset + offset > bb.limit) {
    throw new Error('Skip past limit');
  }
  bb.offset += offset;
}

function isAtEnd(bb) {
  return bb.offset >= bb.limit;
}

function grow(bb, count) {
  let bytes = bb.bytes;
  let offset = bb.offset;
  let limit = bb.limit;
  let finalOffset = offset + count;
  if (finalOffset > bytes.length) {
    let newBytes = new Uint8Array(finalOffset * 2);
    newBytes.set(bytes);
    bb.bytes = newBytes;
  }
  bb.offset = finalOffset;
  if (finalOffset > limit) {
    bb.limit = finalOffset;
  }
  return offset;
}

function advance(bb, count) {
  let offset = bb.offset;
  if (offset + count > bb.limit) {
    throw new Error('Read past limit');
  }
  bb.offset += count;
  return offset;
}

function readBytes(bb, count) {
  let offset = advance(bb, count);
  return bb.bytes.subarray(offset, offset + count);
}

function writeBytes(bb, buffer) {
  let offset = grow(bb, buffer.length);
  bb.bytes.set(buffer, offset);
}

function readString(bb, count) {
  // Sadly a hand-coded UTF8 decoder is much faster than subarray+TextDecoder in V8
  let offset = advance(bb, count);
  let fromCharCode = String.fromCharCode;
  let bytes = bb.bytes;
  let invalid = '\uFFFD';
  let text = '';

  for (let i = 0; i < count; i++) {
    let c1 = bytes[i + offset], c2, c3, c4, c;

    // 1 byte
    if ((c1 & 0x80) === 0) {
      text += fromCharCode(c1);
    }

    // 2 bytes
    else if ((c1 & 0xE0) === 0xC0) {
      if (i + 1 >= count) text += invalid;
      else {
        c2 = bytes[i + offset + 1];
        if ((c2 & 0xC0) !== 0x80) text += invalid;
        else {
          c = ((c1 & 0x1F) << 6) | (c2 & 0x3F);
          if (c < 0x80) text += invalid;
          else {
            text += fromCharCode(c);
            i++;
          }
        }
      }
    }

    // 3 bytes
    else if ((c1 & 0xF0) == 0xE0) {
      if (i + 2 >= count) text += invalid;
      else {
        c2 = bytes[i + offset + 1];
        c3 = bytes[i + offset + 2];
        if (((c2 | (c3 << 8)) & 0xC0C0) !== 0x8080) text += invalid;
        else {
          c = ((c1 & 0x0F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F);
          if (c < 0x0800 || (c >= 0xD800 && c <= 0xDFFF)) text += invalid;
          else {
            text += fromCharCode(c);
            i += 2;
          }
        }
      }
    }

    // 4 bytes
    else if ((c1 & 0xF8) == 0xF0) {
      if (i + 3 >= count) text += invalid;
      else {
        c2 = bytes[i + offset + 1];
        c3 = bytes[i + offset + 2];
        c4 = bytes[i + offset + 3];
        if (((c2 | (c3 << 8) | (c4 << 16)) & 0xC0C0C0) !== 0x808080) text += invalid;
        else {
          c = ((c1 & 0x07) << 0x12) | ((c2 & 0x3F) << 0x0C) | ((c3 & 0x3F) << 0x06) | (c4 & 0x3F);
          if (c < 0x10000 || c > 0x10FFFF) text += invalid;
          else {
            c -= 0x10000;
            text += fromCharCode((c >> 10) + 0xD800, (c & 0x3FF) + 0xDC00);
            i += 3;
          }
        }
      }
    }

    else text += invalid;
  }

  return text;
}

function writeString(bb, text) {
  // Sadly a hand-coded UTF8 encoder is much faster than TextEncoder+set in V8
  let n = text.length;
  let byteCount = 0;

  // Write the byte count first
  for (let i = 0; i < n; i++) {
    let c = text.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < n) {
      c = (c << 10) + text.charCodeAt(++i) - 0x35FDC00;
    }
    byteCount += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
  }
  writeVarint32(bb, byteCount);

  let offset = grow(bb, byteCount);
  let bytes = bb.bytes;

  // Then write the bytes
  for (let i = 0; i < n; i++) {
    let c = text.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < n) {
      c = (c << 10) + text.charCodeAt(++i) - 0x35FDC00;
    }
    if (c < 0x80) {
      bytes[offset++] = c;
    } else {
      if (c < 0x800) {
        bytes[offset++] = ((c >> 6) & 0x1F) | 0xC0;
      } else {
        if (c < 0x10000) {
          bytes[offset++] = ((c >> 12) & 0x0F) | 0xE0;
        } else {
          bytes[offset++] = ((c >> 18) & 0x07) | 0xF0;
          bytes[offset++] = ((c >> 12) & 0x3F) | 0x80;
        }
        bytes[offset++] = ((c >> 6) & 0x3F) | 0x80;
      }
      bytes[offset++] = (c & 0x3F) | 0x80;
    }
  }
}

function writeByteBuffer(bb, buffer) {
  let offset = grow(bb, buffer.limit);
  let from = bb.bytes;
  let to = buffer.bytes;

  // This for loop is much faster than subarray+set on V8
  for (let i = 0, n = buffer.limit; i < n; i++) {
    from[i + offset] = to[i];
  }
}

function readByte(bb) {
  return bb.bytes[advance(bb, 1)];
}

function writeByte(bb, value) {
  let offset = grow(bb, 1);
  bb.bytes[offset] = value;
}

function readFloat(bb) {
  let offset = advance(bb, 4);
  let bytes = bb.bytes;

  // Manual copying is much faster than subarray+set in V8
  f32_u8[0] = bytes[offset++];
  f32_u8[1] = bytes[offset++];
  f32_u8[2] = bytes[offset++];
  f32_u8[3] = bytes[offset++];
  return f32[0];
}

function writeFloat(bb, value) {
  let offset = grow(bb, 4);
  let bytes = bb.bytes;
  f32[0] = value;

  // Manual copying is much faster than subarray+set in V8
  bytes[offset++] = f32_u8[0];
  bytes[offset++] = f32_u8[1];
  bytes[offset++] = f32_u8[2];
  bytes[offset++] = f32_u8[3];
}

function readDouble(bb) {
  let offset = advance(bb, 8);
  let bytes = bb.bytes;

  // Manual copying is much faster than subarray+set in V8
  f64_u8[0] = bytes[offset++];
  f64_u8[1] = bytes[offset++];
  f64_u8[2] = bytes[offset++];
  f64_u8[3] = bytes[offset++];
  f64_u8[4] = bytes[offset++];
  f64_u8[5] = bytes[offset++];
  f64_u8[6] = bytes[offset++];
  f64_u8[7] = bytes[offset++];
  return f64[0];
}

function writeDouble(bb, value) {
  let offset = grow(bb, 8);
  let bytes = bb.bytes;
  f64[0] = value;

  // Manual copying is much faster than subarray+set in V8
  bytes[offset++] = f64_u8[0];
  bytes[offset++] = f64_u8[1];
  bytes[offset++] = f64_u8[2];
  bytes[offset++] = f64_u8[3];
  bytes[offset++] = f64_u8[4];
  bytes[offset++] = f64_u8[5];
  bytes[offset++] = f64_u8[6];
  bytes[offset++] = f64_u8[7];
}

function readInt32(bb) {
  let offset = advance(bb, 4);
  let bytes = bb.bytes;
  return (
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24)
  );
}

function writeInt32(bb, value) {
  let offset = grow(bb, 4);
  let bytes = bb.bytes;
  bytes[offset] = value;
  bytes[offset + 1] = value >> 8;
  bytes[offset + 2] = value >> 16;
  bytes[offset + 3] = value >> 24;
}

function readInt64(bb, unsigned) {
  return {
    low: readInt32(bb),
    high: readInt32(bb),
    unsigned,
  };
}

function writeInt64(bb, value) {
  writeInt32(bb, value.low);
  writeInt32(bb, value.high);
}

function readVarint32(bb) {
  let c = 0;
  let value = 0;
  let b;
  do {
    b = readByte(bb);
    if (c < 32) value |= (b & 0x7F) << c;
    c += 7;
  } while (b & 0x80);
  return value;
}

function writeVarint32(bb, value) {
  value >>>= 0;
  while (value >= 0x80) {
    writeByte(bb, (value & 0x7f) | 0x80);
    value >>>= 7;
  }
  writeByte(bb, value);
}

function readVarint64(bb, unsigned) {
  let part0 = 0;
  let part1 = 0;
  let part2 = 0;
  let b;

  b = readByte(bb); part0 = (b & 0x7F); if (b & 0x80) {
    b = readByte(bb); part0 |= (b & 0x7F) << 7; if (b & 0x80) {
      b = readByte(bb); part0 |= (b & 0x7F) << 14; if (b & 0x80) {
        b = readByte(bb); part0 |= (b & 0x7F) << 21; if (b & 0x80) {

          b = readByte(bb); part1 = (b & 0x7F); if (b & 0x80) {
            b = readByte(bb); part1 |= (b & 0x7F) << 7; if (b & 0x80) {
              b = readByte(bb); part1 |= (b & 0x7F) << 14; if (b & 0x80) {
                b = readByte(bb); part1 |= (b & 0x7F) << 21; if (b & 0x80) {

                  b = readByte(bb); part2 = (b & 0x7F); if (b & 0x80) {
                    b = readByte(bb); part2 |= (b & 0x7F) << 7;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  return {
    low: part0 | (part1 << 28),
    high: (part1 >>> 4) | (part2 << 24),
    unsigned,
  };
}

function writeVarint64(bb, value) {
  let part0 = value.low >>> 0;
  let part1 = ((value.low >>> 28) | (value.high << 4)) >>> 0;
  let part2 = value.high >>> 24;

  // ref: src/google/protobuf/io/coded_stream.cc
  let size =
    part2 === 0 ?
      part1 === 0 ?
        part0 < 1 << 14 ?
          part0 < 1 << 7 ? 1 : 2 :
          part0 < 1 << 21 ? 3 : 4 :
        part1 < 1 << 14 ?
          part1 < 1 << 7 ? 5 : 6 :
          part1 < 1 << 21 ? 7 : 8 :
      part2 < 1 << 7 ? 9 : 10;

  let offset = grow(bb, size);
  let bytes = bb.bytes;

  switch (size) {
    case 10: bytes[offset + 9] = (part2 >>> 7) & 0x01;
    case 9: bytes[offset + 8] = size !== 9 ? part2 | 0x80 : part2 & 0x7F;
    case 8: bytes[offset + 7] = size !== 8 ? (part1 >>> 21) | 0x80 : (part1 >>> 21) & 0x7F;
    case 7: bytes[offset + 6] = size !== 7 ? (part1 >>> 14) | 0x80 : (part1 >>> 14) & 0x7F;
    case 6: bytes[offset + 5] = size !== 6 ? (part1 >>> 7) | 0x80 : (part1 >>> 7) & 0x7F;
    case 5: bytes[offset + 4] = size !== 5 ? part1 | 0x80 : part1 & 0x7F;
    case 4: bytes[offset + 3] = size !== 4 ? (part0 >>> 21) | 0x80 : (part0 >>> 21) & 0x7F;
    case 3: bytes[offset + 2] = size !== 3 ? (part0 >>> 14) | 0x80 : (part0 >>> 14) & 0x7F;
    case 2: bytes[offset + 1] = size !== 2 ? (part0 >>> 7) | 0x80 : (part0 >>> 7) & 0x7F;
    case 1: bytes[offset] = size !== 1 ? part0 | 0x80 : part0 & 0x7F;
  }
}

function readVarint32ZigZag(bb) {
  let value = readVarint32(bb);

  // ref: src/google/protobuf/wire_format_lite.h
  return (value >>> 1) ^ -(value & 1);
}

function writeVarint32ZigZag(bb, value) {
  // ref: src/google/protobuf/wire_format_lite.h
  writeVarint32(bb, (value << 1) ^ (value >> 31));
}

function readVarint64ZigZag(bb) {
  let value = readVarint64(bb, /* unsigned */ false);
  let low = value.low;
  let high = value.high;
  let flip = -(low & 1);

  // ref: src/google/protobuf/wire_format_lite.h
  return {
    low: ((low >>> 1) | (high << 31)) ^ flip,
    high: (high >>> 1) ^ flip,
    unsigned: false,
  };
}

function writeVarint64ZigZag(bb, value) {
  let low = value.low;
  let high = value.high;
  let flip = high >> 31;

  // ref: src/google/protobuf/wire_format_lite.h
  writeVarint64(bb, {
    low: (low << 1) ^ flip,
    high: ((high << 1) | (low >>> 31)) ^ flip,
    unsigned: false,
  });
}
