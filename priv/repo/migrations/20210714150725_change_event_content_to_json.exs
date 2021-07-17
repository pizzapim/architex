defmodule MatrixServer.Repo.Migrations.ChangeEventContentToJson do
  use Ecto.Migration

  def change do
    execute(
      "alter table events alter column content type jsonb using (content::jsonb);",
      "alter table events alter column content type character varying(255);"
    )
  end
end
