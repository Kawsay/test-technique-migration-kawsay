# Contrat que tout adaptateur doit respecter pour être substituable à un autre.
#
# Le spec qui l'inclut définit `file_with(rows)` : crée un fichier au format de l'adaptateur,
# contenant ces lignes (tableaux de textes, [] pour une ligne vide), et renvoie l'adaptateur qui le lit.
RSpec.shared_examples "an adapter" do
  it "returns rows in file order, numbered from 1" do
    rows = file_with([["Ref", "Nom"], ["REF1", "Rouge"], ["REF2", "Blanc"]]).rows

    expect(rows).to all(be_an(Importer::Adapter::Row))
    expect(rows.map { |row| row.line }).to eq([1, 2, 3])
    expect(rows.map { |row| row.values.first }).to eq(["Ref", "REF1", "REF2"])
  end

  it "keeps empty rows so that line numbers stay exact" do
    rows = file_with([["Ref"], [], ["REF1"]]).rows

    expect(rows.map { |row| row.line }).to eq([1, 2, 3])
    expect(rows[1].values.compact).to be_empty
  end

  it "does not clean the values" do
    expect(file_with([["  REF1  "]]).rows.first.values.first).to eq("  REF1  ")
  end
end
