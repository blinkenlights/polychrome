defmodule Octopus.Story do
  import NimbleParsec

  @enforce_keys [:lines]
  defstruct lines: []

  @type option() :: :direct_speech

  @type line() :: %{
          text: String.t(),
          duration: non_neg_integer(),
          options: [option()]
        }

  @type t() :: %__MODULE__{
          lines: [line()]
        }
  defp map_line([duration, text]), do: map_line([duration, [], text])

  defp map_line([duration, options, text]) do
    text = text |> List.wrap() |> Enum.join()
    %{duration: duration, options: Enum.uniq(options), text: String.upcase(text)}
  end

  defp map_story(lines) do
    %__MODULE__{lines: lines}
  end

  duration = integer(min: 1)

  text =
    ignore(string(" ")) |> utf8_string([{:not, ?\n}], min: 0, max: 10) |> map({String, :trim, []})

  options =
    ignore(string(" "))
    |> choice([
      utf8_char([?>]) |> replace(:direct_speech),
      utf8_char([?#]) |> replace(:some_effect)
    ])
    |> repeat()
    |> wrap()

  defcombinatorp(
    :line,
    duration
    |> concat(optional(options))
    |> concat(optional(text))
    |> ignore(string("\n"))
    |> wrap()
    |> map({:map_line, []})
  )

  defparsecp(
    :parse_story,
    repeat(parsec(:line))
    |> wrap()
    |> map({:map_story, []})
    |> eos(),
    debug: true
  )

  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t(), String.t()}
  def parse(string) do
    case parse_story(string) do
      {:ok, [story], "", %{}, _, _} -> {:ok, story}
      {:error, reason, found, _, _, _} -> {:error, reason, found}
    end
  end

  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()} | {:error, String.t(), String.t()}
  def load(name) do
    path = Path.join([:code.priv_dir(:octopus), "stories", "#{name}.txt"])

    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, reason}
    end
  end
end
