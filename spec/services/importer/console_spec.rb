require "spec_helper"

RSpec.describe Importer::Console do
  # La sortie des tests n'est pas un terminal : le texte doit rester brut, sans codes de couleur.
  it "writes plain text when the output is not a terminal" do
    expect(described_class.paint("4988 créés", :bold, :green)).to eq("4988 créés")
  end

  it "colours the text when the output is a terminal" do
    allow(described_class).to receive(:colors?).and_return(true)

    expect(described_class.paint("ÉCART", :red)).to eq("\e[31mÉCART\e[0m")
  end

  it "writes a title that fills the width" do
    expect(described_class.title("Import des clients CaveGest"))
      .to eq("\n── Import des clients CaveGest ".ljust(described_class::WIDTH + 1, "─"))
  end
end
