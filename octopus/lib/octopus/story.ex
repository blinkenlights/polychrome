defmodule Octopus.Story do
  @enforce_keys [:lines]
  defstruct lines: []

  @type option() :: :direct_speech

  @type line() ::
          {:text, String.t()}
          | {:pause, :short | :long}

  @type t() :: %__MODULE__{
          lines: [line()]
        }

  @spec parse(String.t()) :: t()
  def parse(string) do
    string
    |> String.replace(~r/[,.]+/, " \\0")
    |> String.split(" ", trim: true)
    |> Enum.map(&parse_token/1)
    |> combine()
    |> put_word_pauses()
  end

  defp parse_token(","), do: {:pause, :comma}
  defp parse_token("."), do: {:pause, :period}
  defp parse_token(token), do: {:text, String.split(token, "", trim: true), []}

  defp combine(tokens) do
    combine(tokens, [])
  end

  defp combine([], acc), do: Enum.reverse(acc)

  defp combine([{:text, text, opts}, {:pause, pause} | rest], acc) do
    combine(rest, [{:text, text, Keyword.merge(opts, pause: pause)} | acc])
  end

  defp combine([token | rest], acc) do
    combine(rest, [token | acc])
  end

  defp put_word_pauses(tokens) do
    Enum.intersperse(tokens, {:text, [], pause: :blank})
  end

  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(name) do
    path = Path.join([:code.priv_dir(:octopus), "stories", "#{name}.txt"])

    case File.read(path) do
      {:ok, content} -> {:ok, parse(content)}
      {:error, reason} -> {:error, reason}
    end
  end
end
