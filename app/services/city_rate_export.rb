require "caxlsx"

# City rate list (one rate per city, used for DA and Lodging) – download, change and upload back.
class CityRateExport
  HEADERS = [ "City", "State", "Rate (DA & Lodging)", "Active" ].freeze

  def initialize(cities) = @cities = cities

  def to_xlsx
    pkg = Axlsx::Package.new
    pkg.workbook.add_worksheet(name: "Cities") do |ws|
      head  = ws.styles.add_style(b: true, bg_color: "1F8445", fg_color: "FFFFFF", alignment: { horizontal: :center })
      money = ws.styles.add_style(format_code: "0.00")
      ws.add_row HEADERS, style: head
      @cities.each do |c|
        ws.add_row [ c.name, c.state, c.da_rate&.to_f, c.active? ? "Yes" : "No" ],
                   types: [ :string, :string, :float, :string ], style: [ nil, nil, money, nil ]
      end
      ws.column_widths 28, 20, 18, 8
      ws.sheet_view.pane { |p| p.top_left_cell = "A2"; p.state = :frozen; p.y_split = 1 }
    end
    pkg.to_stream.read
  end
end
