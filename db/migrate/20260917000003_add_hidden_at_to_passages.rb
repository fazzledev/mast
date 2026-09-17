# A passage you never want to type again is hidden rather than deleted, so its
# record of battles stays and it can be shown again.
class AddHiddenAtToPassages < Mast::Migration
  def up
    execute "ALTER TABLE passages ADD COLUMN hidden_at REAL"
  end
end
