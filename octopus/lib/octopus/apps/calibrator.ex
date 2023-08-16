defmodule Octopus.Apps.Calibrator do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.{ColorPalette, Broadcaster}
  alias Octopus.Protobuf.{WFrame}

  @moduledoc """
  This app is used to calibrate the display. It reads colors from DisplayCal and renders them on the pixels.
  The red, green and blue corrections values can be adjusted during the initial setup.any()
  See `calibration/README.md` for more information.
  """

  defmodule State do
    defstruct [:color, :data]
  end

  defmodule RGBW do
    defstruct [:r, :g, :b, :w]
  end

  defmodule RGB do
    defstruct [:r, :g, :b]
  end

  @pixel_index 6

  @first_color "808080"
  @display_cal_endpoint "http://localhost:8080/ajax/messages"
  @red_correction 1.0
  @green_correction 0.86
  @blue_correction 0.46
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

  def name(), do: "Calibrator"

  def init(_args) do
    data =
      0..(640 - 1)
      |> Enum.map(fn _ -> 1 end)
      |> IO.iodata_to_binary()

    state = %State{
      color: color_from_hex(@first_color),
      data: data
    }

    Broadcaster.set_calibration(false)

    :timer.send_interval(200, :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = set_next_color(state)

    palette =
      %ColorPalette{
        colors: [
          %RGBW{r: 0, g: 0, b: 0, w: 0},
          state.color |> apply_corrections()
        ]
      }
      |> encode_palette()

    send_frame(%WFrame{data: state.data, palette: palette})

    {:noreply, state}
  end

  def color_from_hex(<<r::binary-2, g::binary-2, b::binary-2>>) do
    {r, ""} = Integer.parse(r, 16)
    {g, ""} = Integer.parse(g, 16)
    {b, ""} = Integer.parse(b, 16)

    %RGB{r: r, g: g, b: b}
  end

  def set_next_color(%State{color: color = %RGB{}} = state) do
    query = URI.encode("rgb(#{color.r}, #{color.g}, #{color.b}) 0.5")

    Finch.build(:get, "#{@display_cal_endpoint}?" <> query)
    |> Finch.request(Octopus.Finch, receive_timeout: 120_000)
    |> case do
      {:ok, %Finch.Response{status: 200, body: "#" <> new_color}} ->
        color =
          color_from_hex(new_color)
          |> tap(fn c -> Logger.info("Got new color from DisplayCal: #{inspect(c)}") end)

        %State{state | color: color}

      {:error, reason} ->
        Logger.warning("DisplayCal request error: #{inspect(reason)}")
        state
    end
  end

  def apply_corrections(%RGB{r: r, g: g, b: b}) do
    # first gamma, then corrections
    # %RGBW{
    #   r: round(Enum.at(@gamma_lookup, 180)),
    #   g: round(Enum.at(@gamma_lookup, 255)),
    #   b: round(Enum.at(@gamma_lookup, 180)),
    #   w: round(Enum.at(@gamma_lookup, 255))
    # }
    %RGBW{
      r: round(Enum.at(@gamma_lookup, r) * @red_correction),
      g: round(Enum.at(@gamma_lookup, g) * @green_correction),
      b: round(Enum.at(@gamma_lookup, b) * @blue_correction),
      w: 0
    }

    # %RGBW{r: 0, g: 0, b: 30, w: 255}
  end

  def encode_palette(%ColorPalette{colors: colors}) do
    colors
    |> Enum.flat_map(fn
      %RGB{r: r, g: g, b: b} -> [r, g, b]
      %RGBW{r: r, g: g, b: b, w: w} -> [r, g, b, w]
    end)
    |> IO.iodata_to_binary()
  end
end
