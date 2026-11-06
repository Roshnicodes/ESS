# PD Finance can mark a claim "Under process" (and print it) before the Project / BLI is filled;
# the claim stays pending with Finance until it is approved with the coding.
class AddUnderProcessToTourClaims < ActiveRecord::Migration[8.1]
  def change
    add_column :tour_claims, :under_process_at, :datetime
    add_reference :tour_claims, :under_process_by, foreign_key: { to_table: :users }, index: false
    add_index :tour_claims, :under_process_at, where: "under_process_at IS NOT NULL"
  end
end
