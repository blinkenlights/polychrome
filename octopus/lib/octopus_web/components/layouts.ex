defmodule OctopusWeb.Layouts do
  use OctopusWeb, :html

  import OctopusWeb.TopBarComponent

  embed_templates "layouts/*"
end
