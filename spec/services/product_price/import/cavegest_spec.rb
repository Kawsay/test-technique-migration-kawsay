require "spec_helper"

RSpec.describe ProductPrice::Import::Cavegest do
  def import(path) = described_class.new(path).call

  describe "with the client's actual file" do
    let(:path) { data_path("export_tarifs_cavegest.csv") }

    it "reads a Windows-1252 encoded file" do
      expect { import(path) }.not_to raise_error
    end

    it "does not use the preamble line as the header" do
      transcoded = File.join(Dir.mktmpdir, "tarifs_utf8.csv")
      File.write(transcoded, File.read(path, encoding: "Windows-1252:UTF-8"))

      expect { import(transcoded) }.to change(Product, :count).by_at_least(100)
    end
  end

  describe "with a simplified extract" do
    it "does not create a price for an empty grid" do
      # empty value at position -2 (field SALON)
      import(simplified_tariffs_csv("LANM3;La Pierre Blanche;BIB - 300.0;Rouge;20;13.32;11.72;15.98;15.72;;112"))

      expect(ProductPrice.where(grid_code: "SALON")).to be_empty
    end

    it "converts the EXPO grid to excl. VAT using the product's own VAT rate" do
      # EXPO TTC 31,01 à 5,5 % -> 29,39 HT (= DEPC), et non 31,01 / 1,2 = 25,84
      import(simplified_tariffs_csv("CUV239;Eau de source 2023;BIB - 300.0;blanc;5.50;29.39;25.86;31.01;34.68;;660"))

      expect(ProductPrice.find_by!(grid_code: "EXPO").amount_ht).to eq(BigDecimal("29.39"))
    end

    it "parses a half-bottle container (37.5 cl)" do
      import(simplified_tariffs_csv("CUV234;Cuvée Marie 2023;½ Bouteille - 37.5;blanc;20;11.77;10.36;14.12;13.89;12.95;396"))

      expect(Product.find_by!(reference: "CUV234").volume_ml).to eq(375)
    end

    it "does not guess a volume from a '6 x 75' packaging" do
      import(simplified_tariffs_csv("TRA195;Tradition 2019;6 x 75;;20;23.41;20.60;28.09;27.62;;607"))

      expect(Product.find_by!(reference: "TRA195").volume_ml).to be_nil
    end

    it "does not abort on a duplicated reference" do
      path = simplified_tariffs_csv(
        "CUV227;Cuvée Prestige 2022;Bouteille - 75.0;;20;24.91;21.92;29.89;29.39;;136",
        "CUV227;Cuvée Marie 2022;Magnum - 150.0;BLANC;20;12.27;10.80;14.72;14.48;;647"
      )

      expect { import(path) }.not_to raise_error
    end

    it "does not silently pick one version of a conflicting reference" do
      path = simplified_tariffs_csv(
        "CUV227;Cuvée Prestige 2022;Bouteille - 75.0;;20;24.91;21.92;29.89;29.39;;136",
        "LES205;Les Argiles 2020;Bouteille - 75.0;Blanc;20;26.16;23.02;31.39;30.87;;49",
        "CUV227;Cuvée Marie 2022;Magnum - 150.0;BLANC;20;12.27;10.80;14.72;14.48;;647"
      )

      import(path) rescue nil

      expect(Product.where(reference: "CUV227")).to be_empty
    end

    it "does not import a section line as a product" do
      import(simplified_tariffs_csv("--- AOP ROUGES ---;;;;;;;;;;"))

      expect(Product.where("reference LIKE '---%'")).to be_empty
    end

    it "does not import a subtotal line as a product" do
      import(simplified_tariffs_csv("SOUS-TOTAL AOP ROUGES;;;;;;;;;;14"))

      expect(Product.where("reference LIKE 'SOUS-TOTAL%'")).to be_empty
    end
  end
end
