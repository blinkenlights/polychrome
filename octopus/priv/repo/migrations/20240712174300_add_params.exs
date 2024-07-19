defmodule Octopus.Repo.Migrations.AddParams do
  use Ecto.Migration

  def change do
    create table(:params) do
      add :params, :binary
      timestamps()
    end
  end
end
