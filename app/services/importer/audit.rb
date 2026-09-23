# Contrôles de cohérence passés sur la base après une reprise.
#
# Ils sont calculés depuis la base, et non depuis les fichiers ni depuis le journal de l'import : c'est ce
# qui permet d'affirmer au client que ses données sont justes, quelle que soit la façon dont elles sont
# arrivées là. Un contrôle qui trouve des anomalies ne lève rien : il les nomme.
#
# equal_price_grids - Array de paires de grilles dont les prix HT doivent être égaux chez ce client
#                     (ex. [["EXPO", "DEPC"]], voir Importer::Cavegest::ProductPricesLayout).
#                     Vide par défaut : deux grilles portent des prix différents, c'est leur raison d'être.
class Importer::Audit
  # Le résultat d'un contrôle.
  #
  # label   - String, ce que le contrôle vérifie.
  # records - Array de String, tous les enregistrements en écart, nommés pour aller les voir ;
  #           vide si le contrôle passe. Ils sont tous cités : une reprise se vérifie en entier.
  Finding = Data.define(:label, :records) do
    def ok? = records.empty?
  end

  # Écart toléré entre deux prix censés être égaux : l'arrondi au centime de la conversion TTC => HT.
  PRICE_TOLERANCE = BigDecimal("0.01")

  def self.call(...) = new(...).call

  def initialize(equal_price_grids: [])
    @equal_price_grids = equal_price_grids
  end

  # Renvoie un Finding par contrôle, dans l'ordre où ils sont présentés.
  def call
    [
      products_without_price,
      prices_not_positive,
      unknown_vat_rates,
      products_outside_vocabulary,
      customer_grids_without_price,
      price_grids_without_customer,
      invalid_country_codes,
      *unequal_price_grids
    ]
  end

  def to_s
    counts = "#{Customer.count} clients, #{Product.count} produits, #{ProductPrice.count} tarifs en base"
    lines  = call.map { |finding| format("%-6s %s", finding.ok? ? "OK" : "ÉCART", detail(finding)) }

    ["Contrôles après reprise — #{counts}", *lines].join("\n")
  end

  private

  def detail(finding)
    return finding.label if finding.ok?

    "#{finding.label} : #{finding.records.size} (#{finding.records.join(', ')})"
  end

  def products_without_price
    records = Product.where.missing(:product_prices).pluck(:reference)

    finding("Chaque produit a au moins un tarif", records)
  end

  def prices_not_positive
    prices  = ProductPrice.joins(:product).where(amount_ht: ..0).pluck("products.reference", :grid_code)
    records = prices.map { |reference, grid_code| "#{reference} #{grid_code}" }

    finding("Tous les tarifs sont strictement positifs", records)
  end

  def unknown_vat_rates
    records = Product.where.not(vat_rate: Importer::Parsers::FRENCH_VAT_RATES).pluck(:reference)

    finding("Tous les taux de TVA sont applicables en France", records)
  end

  # Les colonnes du vocabulaire Baqio ne doivent porter que les valeurs prévues (voir Product).
  def products_outside_vocabulary
    products = Product.where.not(color:     [nil, *Product::WINE_COLORS])
      .or(Product.where.not(appellation:    [nil, *Product::APPELLATIONS]))
      .or(Product.where.not(product_type:   [nil, *Product::PRODUCT_TYPES]))
      .or(Product.where.not(container_type: [nil, *Product::CONTAINER_TYPES]))
    records = products.pluck(:reference)

    finding("Les produits n'emploient que le vocabulaire Baqio", records)
  end

  # Un client dont la grille n'a aucun tarif n'aurait aucun prix dans Baqio.
  def customer_grids_without_price
    grids     = ProductPrice.distinct.pluck(:grid_code)
    customers = Customer.where.not(price_grid_code: [nil, *grids]).pluck(:reference, :price_grid_code)
    records   = customers.map { |reference, grid_code| "#{reference} (#{grid_code})" }

    finding("Chaque grille tarifaire utilisée par un client a des tarifs", records)
  end

  # Une grille tarifaire que personne n'utilise : soit des clients manquent, soit elle n'a plus lieu d'être.
  def price_grids_without_customer
    records = ProductPrice.distinct.pluck(:grid_code) - Customer.distinct.pluck(:price_grid_code)

    finding("Chaque grille tarifaire est utilisée par au moins un client", records)
  end

  def invalid_country_codes
    codes     = ISO3166::Country.codes
    customers = Customer.where.not(country_code: [nil, *codes]).or(Customer.where.not(shipping_country_code: [nil, *codes]))
    records   = customers.pluck(:reference)

    finding("Les pays sont des codes ISO 3166-1", records)
  end

  # Deux grilles censées porter le même prix HT : un écart signale une erreur de saisie restée en base.
  def unequal_price_grids
    @equal_price_grids.map do |reference_grid, checked_grid|
      amounts = amounts_by_product(reference_grid, checked_grid)
      records = amounts.filter_map do |reference, prices|
        expected = prices[reference_grid]
        found    = prices[checked_grid]

        reference if expected && found && (expected - found).abs > PRICE_TOLERANCE
      end

      finding("Les grilles #{reference_grid} et #{checked_grid} portent les mêmes prix", records)
    end
  end

  # { référence du produit => { grille => montant HT } }, pour les grilles demandées.
  def amounts_by_product(*grid_codes)
    prices = ProductPrice.joins(:product).where(grid_code: grid_codes).pluck("products.reference", :grid_code, :amount_ht)

    prices.group_by { |reference, _grid_code, _amount| reference }
      .transform_values { |found| found.to_h { |_reference, grid_code, amount| [grid_code, amount] } }
  end

  # Tous les contrôles passent par ici : un libellé, et les enregistrements en écart.
  def finding(label, records)
    Finding.new(label: label, records: records.map { |record| record.to_s })
  end
end
