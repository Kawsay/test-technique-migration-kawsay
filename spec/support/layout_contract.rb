# Lignes d'un fichier, numérotées à partir de 1, telles que les produit un adaptateur.
module LayoutHelpers
  def rows(lines)
    lines.each_with_index.map do |values, index|
      Importer::Adapter::Row.new(line: index + 1, values: values)
    end
  end
end

RSpec.configure { |config| config.include LayoutHelpers }

# Contrat que toute disposition doit respecter pour être substituable à une autre.
#
# Le spec qui l'inclut définit :
# - `header`            : Array des en-têtes attendus par la disposition ;
# - `data_row(value)`   : Array des valeurs d'une ligne de données valide, `value` dans la première colonne ;
# - `layout_with(rows)` : la disposition construite sur ces Importer::Adapter::Row.
RSpec.shared_examples "a layout" do
  it "returns a record for each data row, with its line number in the file" do
    records = layout_with(rows([header, data_row("REF1"), data_row("REF2")])).records

    expect(records).to all(be_an(Importer::Layout::Base::Record))
    expect(records.map { |record| record.line }).to eq([2, 3])
  end

  it "names every expected column" do
    record = layout_with(rows([header, data_row("REF1")])).records.first

    expect(record.cells.size).to eq(header.size)
    expect(record.cells.values.first).to eq("REF1")
  end

  it "skips empty rows" do
    records = layout_with(rows([header, data_row("REF1"), Array.new(header.size), data_row("REF2")])).records

    expect(records.map { |record| record.line }).to eq([2, 4])
  end

  it "rejects a file without a header row" do
    expect { layout_with(rows([])).records }.to raise_error(Importer::FileRejected, "header row missing")
  end

  it "rejects a file whose header differs" do
    unexpected_header = ["Autre"] + header.drop(1)

    expect { layout_with(rows([unexpected_header])).records }
      .to raise_error(Importer::FileRejected, "unexpected header (column 1: expected \"#{header.first}\", found \"Autre\")")
  end

  it "reports a column beyond the expected ones, without rejecting the file" do
    layout = layout_with(rows([header + ["Remarque"], data_row("REF1") + ["Livrer le matin"]]))

    expect(layout.records.size).to eq(1)
    expect(layout.ignored_columns).to eq([Importer::Layout::Base::IgnoredColumn.new(position: header.size, name: "Remarque", filled: 1)])
  end
end
