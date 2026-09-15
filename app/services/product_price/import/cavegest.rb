class ProductPrice::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  COLUMN_SEP = ";".freeze
  GRID_CODES = %w[DEPC CHR EXPO PART SALON].freeze

  def call
    imported = 0

    CSV.parse(File.read(path), headers: true, col_sep: COLUMN_SEP).each do |row|
      reference = N.text(row["Ref"])
      next if reference.nil?

      product = Product.create!(
        reference: reference,
        name:      N.text(row["Désignation"]),
        color:     N.text(row["Couleur"]),
        volume_ml: volume_ml(row["Contenant"]),
        vat_rate:  N.decimal(row["TVA"]),
        stock:     N.decimal(row["Stock"]).to_i
      )

      import_prices(product, row)
      imported += 1
    end

    puts "#{imported} produits importés"
  end

  private

  def import_prices(product, row)
    GRID_CODES.each do |grid_code|
      amount = N.decimal(row[grid_code])

      # La grille EXPO est saisie en TTC dans CaveGest, on stocke du HT.
      amount /= 1.2 if grid_code == "EXPO"

      ProductPrice.create!(
        product:   product,
        grid_code: grid_code,
        amount_ht: amount.round(2)
      )
    end
  end

  def volume_ml(value)
    value.to_s[/\d+/].to_i * 10
  end
end
