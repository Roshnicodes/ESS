# Local mileage after the cutoff day: the employee asks the COO; once approved that month's
# claim may still be filled and sent.  Tour plan: the length at the first approval is kept,
# so an approved tour can be extended by at most 3 days (and never beyond 10 days).
class CreateLateClaimRequests < ActiveRecord::Migration[8.1]
  def up
    create_table :late_claim_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.date :claim_month, null: false
      t.text :reason, null: false
      t.string :status, null: false, default: "pending"
      t.references :approver, foreign_key: { to_table: :users }
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.text :decision_remark
      t.timestamps
    end
    add_index :late_claim_requests, %i[user_id claim_month], unique: true, where: "status IN ('pending', 'approved')",
              name: "index_late_claim_requests_one_open_per_month"
    add_index :late_claim_requests, %i[approver_id status]

    add_column :tours, :approved_days, :integer
    # tours approved before this change: their length today counts as the approved length
    execute <<~SQL
      UPDATE tours SET approved_days = (to_date - from_date) + 1
      WHERE tour_type = 'tour' AND approved_at IS NOT NULL AND from_date IS NOT NULL AND to_date IS NOT NULL
    SQL
  end

  def down
    remove_column :tours, :approved_days
    drop_table :late_claim_requests
  end
end
