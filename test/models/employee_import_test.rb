require "test_helper"
require "caxlsx"

class EmployeeImportTest < ActiveSupport::TestCase
  def xlsx(rows)
    pkg = Axlsx::Package.new
    pkg.workbook.add_worksheet(name: "Sheet1") do |ws|
      ws.add_row EmployeeExport::HEADERS
      rows.each { |r| ws.add_row r }
    end
    path = Rails.root.join("tmp/test_import_#{SecureRandom.hex(4)}.xlsx").to_s
    pkg.serialize(path)
    path
  end

  test "adds new employees with L1/L2, keeps existing unchanged" do
    hr = user("HR001")
    existing = user("AM001")
    path = xlsx([
      [ "Krishn Kumar Trivedi", 840, "k.t@example.org", "8959591213", "01/08/2018", "Operations", "COO", "HO- Bhopal", "HO- Bhopal", "L-1", "", "#N/A", "", "", "#N/A", "" ],
      [ "Pritesh Jain", 25, "p.j@example.org", "7000778069", "16/04/2007", "LWRD", "FCO Coordinator", "FCO-Ranapur", "FCO-Ranapur", "L-2", 840, 840, "Krishn", "", "#N/A", "" ],
      [ "Makhan Singh", 1724, "", "7860345972", "26/09/2025", "Project", "FCO Coordinator", "FCO-Kotma", "TO-Kotma", "L-3", 25, 25, "Pritesh", 840, 840, "Krishn" ],
      [ "Changed Name", "AM001", "", "", "", "", "", "", "", "", "", "", "", "", "", "" ]
    ])
    res = EmployeeImport.new(path, by: hr).call
    assert_equal [ 3, 0, 1 ], [ res.created, res.updated, res.skipped ]
    makhan = User.find_by!(emp_code: "1724")
    assert_equal "25", makhan.reporting_manager.emp_code
    assert_equal "840", makhan.l2_manager.emp_code
    assert_equal "L-3", makhan.level
    assert_equal Date.new(2025, 9, 26), makhan.date_of_joining
    assert makhan.valid_password?("123456")
    assert_equal "Swapnil Amne", existing.reload.name           # existing kept as is

    res2 = EmployeeImport.new(path, by: hr).call                # re-upload: nothing duplicated
    assert_equal [ 0, 4 ], [ res2.created, res2.skipped ]

    res3 = EmployeeImport.new(path, by: hr, mode: :update).call
    assert_equal "Changed Name", existing.reload.name
    assert_equal 4, res3.updated
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "export downloads an xlsx with the same headers" do
    data = EmployeeExport.new(User.all).to_xlsx
    path = Rails.root.join("tmp/export_test.xlsx").to_s
    File.binwrite(path, data)
    sheet = Roo::Excelx.new(path).sheet(0)
    assert_equal EmployeeExport::HEADERS, sheet.row(1)
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
