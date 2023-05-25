#! /usr/bin/env elixir

require Logger

[filename] = System.argv()

defmodule Corrections do
  @red_correction 1.0
  @green_correction 0.92
  @blue_correction 0.44
  @gamma_lookup [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    2,
    2,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    3,
    3,
    4,
    4,
    4,
    4,
    5,
    5,
    5,
    5,
    6,
    6,
    6,
    7,
    7,
    7,
    7,
    8,
    8,
    8,
    9,
    9,
    9,
    10,
    10,
    11,
    11,
    11,
    12,
    12,
    13,
    13,
    14,
    14,
    14,
    15,
    15,
    16,
    16,
    17,
    17,
    18,
    18,
    19,
    19,
    20,
    20,
    21,
    22,
    22,
    23,
    23,
    24,
    25,
    25,
    26,
    26,
    27,
    28,
    28,
    29,
    30,
    30,
    31,
    32,
    33,
    33,
    34,
    35,
    35,
    36,
    37,
    38,
    39,
    39,
    40,
    41,
    42,
    43,
    43,
    44,
    45,
    46,
    47,
    48,
    49,
    50,
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    81,
    82,
    83,
    84,
    85,
    87,
    88,
    89,
    90,
    91,
    93,
    94,
    95,
    97,
    98,
    99,
    101,
    102,
    103,
    105,
    106,
    107,
    109,
    110,
    111,
    113,
    114,
    116,
    117,
    119,
    120,
    122,
    123,
    125,
    126,
    128,
    129,
    131,
    132,
    134,
    135,
    137,
    138,
    140,
    142,
    143,
    145,
    146,
    148,
    150,
    151,
    153,
    155,
    156,
    158,
    160,
    162,
    163,
    165,
    167,
    168,
    170,
    172,
    174,
    176,
    177,
    179,
    181,
    183,
    185,
    187,
    189,
    190,
    192,
    194,
    196,
    198,
    200,
    202,
    203,
    206,
    207,
    210,
    212,
    214,
    216,
    218,
    220,
    222,
    224,
    226,
    228,
    230,
    232,
    234,
    237,
    239,
    241,
    243,
    245,
    247,
    250,
    251,
    255
  ]

  def red(r), do: round(Enum.at(@gamma_lookup, r) * @red_correction)
  def green(g), do: round(Enum.at(@gamma_lookup, g) * @green_correction)
  def blue(b), do: round(Enum.at(@gamma_lookup, b) * @blue_correction)
end

values =
  filename
  |> File.stream!()
  |> Stream.drop_while(&(&1 != "BEGIN_DATA\n"))
  |> Stream.drop(1)
  |> Stream.take_while(&(&1 != "END_DATA\n"))
  |> Stream.map(&String.trim(&1))
  |> Enum.map(fn row ->
    String.split(row, " ")
    |> Enum.map(fn bin -> String.to_float(bin) end)
    |> Enum.map(&round(&1 * 255))
  end)

reds = Enum.map(values, fn [_, r, _, _] -> r end)
greens = Enum.map(values, fn [_, _, g, _] -> g end)
blues = Enum.map(values, fn [_, _, _, b] -> b end)

reds_with_correction =
  0..255
  |> Enum.map(fn r ->
    r = Corrections.red(r)
    Enum.at(reds, r)
  end)

greens_with_corrections =
  0..255
  |> Enum.map(fn g ->
    g = Corrections.green(g)
    Enum.at(greens, g)
  end)

blues_with_corrections =
  0..255
  |> Enum.map(fn b ->
    b = Corrections.blue(b)
    Enum.at(blues, b)
  end)

file = File.open!("Pixel_calibrations.h", [:write])

IO.write(file, "#include \"Pixel.h\"\n\n")

IO.write(
  file,
  "const uint8_t Pixel::calibration_table_r[256] = { #{Enum.join(reds_with_correction, ", ")} };\n"
)

IO.write(
  file,
  "const uint8_t Pixel::calibration_table_g[256] = { #{Enum.join(greens_with_corrections, ", ")} };\n"
)

IO.write(
  file,
  "const uint8_t Pixel::calibration_table_b[256] = { #{Enum.join(blues_with_corrections, ", ")} };\n"
)

File.close(file)
