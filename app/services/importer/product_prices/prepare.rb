class Importer::ProductPrices::Prepare
  Accepted = Data.define(:record, :product, :prices)

  PRICE_TOLERANCE = BigDecimal("0.01")

  def initialize(adapter:, layout_class:, report:)
    @adapter      = adapter
    @layout_class = layout_class
    @report       = report
  end

  # Renvoie un Accepted par ligne retenue. Si le fichier entier est rejeté, renvoie un tableau vide :
  # aucune ligne n'a pu être lue, et le rapport en porte la raison.
  def call
    layout  = @layout_class.new(@adapter.rows)
    records = layout.records

    report_ignored_columns(layout.ignored_columns)

    records.filter_map { |record| import(record, layout.section_for(record)) }
  rescue Importer::FileRejected => error
    @report.add(level: :rejected, code: :file_rejected, source: source, value: error.message)
    []
  end

  private

  def source
    @adapter.file_name
  end

  # Renvoie un Accepted, ou nil si la ligne est rejetée.
  def import(record, section)
    reader  = Importer::ProductPrices::Reader.new(record: record, layout_class: @layout_class)
    product = product_attributes(reader, section)

    result = Importer::ProductPrices::Contract.new.call(product)

    if result.failure?
      report_rejection(record, result, reader)
      return nil
    end

    prices = prices_of(reader, product[:vat_rate])

    reader.notices.each { |notice| report_notice(record, notice) }
    Accepted.new(record: record, product: product, prices: prices)
  end

  def product_attributes(reader, section)
    name      = reader.text(:name)
    container = reader.container(:container) || {}

    {
      reference:           reader.text(:reference),
      name:                name,
      vintage:             Importer::Parsers.vintage(name).value!.value,
      color:               reader.color(:color),
      container_label:     reader.text(:container_label),
      container_type:      container[:type],
      units_per_container: container[:units],
      volume_ml:           container[:volume_ml],
      vat_rate:            reader.vat_rate(:vat_rate),
      stock:               reader.integer(:stock)
    }.merge(classification(reader, section))
  end

  # Niveau d'appellation et type de produit, d'après la section de l'export où figure le produit.
  def classification(reader, section)
    return @layout_class::SECTIONS.fetch(section) if @layout_class::SECTIONS.key?(section)

    reader.note(:section_unknown, field: :product_type, value: nil, raw: section)
    { appellation: nil, product_type: nil }
  end

  # Un tarif par grille renseignée : une grille vide n'a pas de tarif (et non un tarif à 0),
  # un montant illisible ou nul n'est pas repris, sans que le produit soit rejeté.
  def prices_of(reader, vat_rate)
    amounts = {}

    @layout_class::PRICE_GRIDS.each do |grid_code, field|
      if reader.empty_cell?(field)
        reader.note(:price_grid_empty, field: field, value: nil)
        next
      end

      amount = reader.money(field)
      next if amount.nil?

      unless amount.positive?
        reader.note(:amount_not_positive, field: field, value: amount)
        next
      end

      amounts[grid_code] = @layout_class::TTC_GRIDS.include?(grid_code) ? excluding_tax(reader, field, amount, vat_rate) : amount
    end

    check_equal_grids(reader, amounts)

    amounts.map { |grid_code, amount| { grid_code: grid_code, amount_ht: amount } }
  end

  # Prix TTC => HT, avec le taux de TVA du produit, arrondi au centime.
  def excluding_tax(reader, field, amount, vat_rate)
    amount_ht = (amount / (1 + vat_rate / 100)).round(2, BigDecimal::ROUND_HALF_UP)
    reader.note(:price_ttc_converted, field: field, value: amount_ht)

    amount_ht
  end

  # Deux grilles censées porter le même prix HT qui s'écartent : la seconde est signalée,
  # avec le prix qu'elle aurait dû avoir d'après la première.
  def check_equal_grids(reader, amounts)
    @layout_class::EQUAL_PRICE_GRIDS.each do |reference_grid, checked_grid|
      expected = amounts[reference_grid]
      found    = amounts[checked_grid]
      next if expected.nil? || found.nil? || (expected - found).abs <= PRICE_TOLERANCE

      reader.note(:price_grids_inconsistent, field: @layout_class::PRICE_GRIDS.fetch(checked_grid), value: expected)
    end
  end

  def entity(record)
    reference = record.cells[:reference].to_s.strip
    reference.empty? ? nil : "Produit #{reference}"
  end

  def report_notice(record, notice)
    @report.add(level: notice.level, code: notice.code, source: source, line: record.line, entity: entity(record),
                field: notice.field, raw: notice.raw, value: notice.value, cells: record.cells)
  end

  # Une ligne rejetée ne journalise que les raisons de son rejet : ses autres anomalies sont sans objet.
  def report_rejection(record, result, reader)
    result.errors.each do |error|
      field = error.path.first

      @report.add(level: :rejected, code: error.meta.fetch(:code), source: source, line: record.line,
                  entity: entity(record), field: field, raw: field && reader.raw(field), cells: record.cells)
    end
  end

  # Colonne en trop : ignorée ; signalée comme douteuse si elle contient des valeurs, qui ne sont pas reprises.
  # raw : en-tête de la colonne ; value : nombre de lignes où elle est renseignée.
  def report_ignored_columns(ignored_columns)
    ignored_columns.each do |column|
      level = column.filled.zero? ? :info : :suspect
      @report.add(level: level, code: :column_ignored, source: source, entity: "Colonne #{column.position + 1}",
                  raw: column.name, value: column.filled)
    end
  end
end
