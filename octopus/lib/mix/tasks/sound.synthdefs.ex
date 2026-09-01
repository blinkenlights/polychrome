defmodule Mix.Tasks.Sound.Synthdefs do
  @shortdoc "Compiles the SuperCollider SynthDefs in priv/synthdefs"

  @moduledoc """
  Compiles `priv/synthdefs/src/polychrome.scd` into `.scsyndef` files that
  `scsynth` loads at startup.

  This is the only step that needs `sclang`; at runtime Elixir talks to the
  synthesis server directly. The compiled files are checked in, so the
  installation never needs SuperCollider's language.

      mix sound.synthdefs
  """

  use Mix.Task

  @macos_sclang "/Applications/SuperCollider.app/Contents/MacOS/sclang"
  @source "priv/synthdefs/src/polychrome.scd"
  @output "priv/synthdefs"

  @impl true
  def run(_args) do
    sclang = System.find_executable("sclang") || existing(@macos_sclang)
    source = Path.expand(@source, File.cwd!())
    output = Path.expand(@output, File.cwd!())

    cond do
      is_nil(sclang) ->
        Mix.raise("""
        sclang not found.

        Install SuperCollider (macOS: `brew install --cask supercollider`,
        Debian: `apt install supercollider`) or put sclang on your PATH.
        """)

      not File.exists?(source) ->
        Mix.raise("SynthDef source not found: #{source}")

      true ->
        Mix.shell().info("Compiling SynthDefs with #{sclang}")
        {output_text, status} = System.cmd(sclang, [source, output], stderr_to_stdout: true)
        Mix.shell().info(output_text)

        if status != 0 do
          Mix.raise("sclang exited with status #{status}")
        end

        Mix.shell().info("Wrote: #{Enum.join(list_defs(output), ", ")}")
    end
  end

  defp list_defs(output) do
    case File.ls(output) do
      {:ok, files} -> Enum.filter(files, &String.ends_with?(&1, ".scsyndef"))
      _ -> []
    end
  end

  defp existing(path), do: if(File.exists?(path), do: path)
end
