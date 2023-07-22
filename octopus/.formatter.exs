[
  import_deps: [:phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs:
    Enum.flat_map(
      ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"],
      &Path.wildcard/1
    ) -- ["lib/octopus/protobuf/schema.pb.ex"]
]
