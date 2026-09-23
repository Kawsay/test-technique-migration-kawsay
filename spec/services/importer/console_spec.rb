require "spec_helper"

RSpec.describe Importer::Console do
  # NO_COLOR est posé par spec_helper : la sortie des tests ne doit pas dépendre du terminal.
  it "writes plain text when colours are off" do
    expect(described_class.colors?).to be(false)
    expect(described_class.paint("4988 créés", :bold, :green)).to eq("4988 créés")
  end

  it "writes a title that fills the width" do
    expect(described_class.title("Import des clients CaveGest"))
      .to eq("\n── Import des clients CaveGest ".ljust(described_class::WIDTH + 1, "─"))
  end

  describe "when the output is a terminal" do
    before { allow(described_class).to receive(:colors?).and_return(true) }

    it "colours the text" do
      expect(described_class.paint("ÉCART", :red)).to eq("\e[31mÉCART\e[0m")
    end

    it "combines several styles" do
      expect(described_class.paint("Non repris", :red, :bold)).to eq("\e[31m\e[1mNon repris\e[0m")
    end
  end
end
