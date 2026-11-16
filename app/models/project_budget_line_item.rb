class ProjectBudgetLineItem < ApplicationRecord
  belongs_to :project
  belongs_to :budget_line_item
  belongs_to :budget_line_item_code
  belongs_to :created_by, class_name: "User", optional: true

  validates :budget_line_item_code_id, uniqueness: { scope: %i[project_id budget_line_item_id] }

  scope :active, -> { where(active: true) }
  scope :for_project, ->(project_id) { active.where(project_id: project_id) }

  NA = "NA".freeze

  # "NA" coding for claims that belong to no project: Project NA → BLI NA → Code NA. Created (or switched
  # back on) when PD Finance opens an approval, so it is always offered even after a new BLI upload.
  def self.ensure_na!
    project = Project.fetch_or_create!(NA)
    line    = BudgetLineItem.fetch_or_create!(NA)
    code    = BudgetLineItemCode.fetch_or_create!(NA)
    [ project, line, code ].each { |m| m.update_columns(active: true) unless m.active? }
    mapping = find_or_create_by!(project: project, budget_line_item: line, budget_line_item_code: code)
    mapping.update_columns(active: true) unless mapping.active?
    mapping
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
