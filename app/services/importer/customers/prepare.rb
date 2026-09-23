# Import des clients, quel que soit le logiciel source : de chaque ligne du fichier aux attributs d'un Customer.
#
# Rien n'est écrit en base, et aucun Customer n'est construit : #call renvoie, pour chaque ligne retenue,
# les attributs prêts à être écrits et la ligne d'origine (Candidate).
# Les lignes rejetées, les corrections appliquées et les valeurs douteuses sont journalisées dans le rapport.
class Importer::Customers::Prepare
  # record     - Importer::Layout::Base::Record d'origine : numéro de ligne et cellules brutes.
  # attributes - Hash des attributs du Customer.
  Accepted = Data.define(:record, :attributes)

  # Champs d'adresse présents à la fois pour la facturation et pour la livraison (shipping_…).
  ADDRESS_FIELDS = %i[last_name first_name company_name address1 zip city country_code phone].freeze

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

    records.filter_map { |record| import(record) }
  rescue Importer::FileRejected => error
    @report.add(level: :rejected, code: :file_rejected, source: source, value: error.message)
    []
  end

  private

  def source
    @adapter.file_name
  end

  def country_codes
    @country_codes ||= Hash.new do |already_read, raw|
      already_read[raw] = Importer::Parsers.country_code(raw)
    end
  end

  def reader_for(record)
    Importer::Customers::Reader.new(record: record, layout_class: @layout_class, country_codes: country_codes)
  end

  # Renvoie un Accepted, ou nil si la ligne est rejetée.
  def import(record)
    reader     = reader_for(record)
    attributes = billing_attributes(reader)
    attributes = attributes.merge(shipping_attributes(record, attributes))

    result = Importer::Customers::Contract.new.call(attributes)

    if result.failure?
      report_rejection(record, result, reader)
      return nil
    end

    reader.notices.each { |notice| report_notice(record, notice) }
    Accepted.new(record: record, attributes: attributes)
  end

  def billing_attributes(reader)
    country_code = reader.country_code(:country_code)

    {
      reference:         reader.text(:reference),
      company_name:      reader.text(:company_name),
      first_name:        reader.text(:first_name),
      last_name:         reader.text(:last_name),
      address1:          reader.text(:address1),
      zip:               reader.zip(:zip, country_code),
      city:              reader.text(:city),
      country_code:      country_code,
      email:             reader.email(:email),
      phone:             reader.phone(:phone),
      mobile:            reader.phone(:mobile),
      kind:              kind(reader),
      customer_category: reader.label(:customer_category),
      price_grid_code:   reader.text(:price_grid_code),
      vat_number:        reader.text(:vat_number),
      excise_number:     reader.text(:excise_number),
      creation_date:     reader.date(:creation_date),
      active:            reader.flag(:active) != true
    }
  end

  # Adresse de livraison, stockée seulement si elle diffère de l'adresse de facturation.
  #
  # Elle est lue par son propre lecteur : si elle n'est pas stockée, ses événements ne concernent
  # plus aucune valeur en base et ne sont pas journalisés.
  def shipping_attributes(record, billing)
    reader         = reader_for(record)
    shipping_cells = ADDRESS_FIELDS.map { |field| reader.raw(:"shipping_#{field}") }
    return { use_billing_address: true } if shipping_cells.all?(&:nil?)

    shipping_country = reader.country_code(:shipping_country_code)

    shipping = {
      shipping_last_name:    reader.text(:shipping_last_name),
      shipping_first_name:   reader.text(:shipping_first_name),
      shipping_company_name: reader.text(:shipping_company_name),
      shipping_address1:     reader.text(:shipping_address1),
      shipping_zip:          reader.zip(:shipping_zip, shipping_country),
      shipping_city:         reader.text(:shipping_city),
      shipping_country_code: shipping_country,
      shipping_phone:        reader.phone(:shipping_phone)
    }

    same_as_billing = ADDRESS_FIELDS.all? { |field| shipping[:"shipping_#{field}"] == billing[field] }
    return { use_billing_address: true } if same_as_billing

    reader.notices.each { |notice| report_notice(record, notice) }
    shipping.merge(use_billing_address: false)
  end

  # Code famille inconnu : kind reste nil, et la ligne est rejetée par le contrat.
  def kind(reader)
    code        = reader.raw(:kind).to_s.strip
    kind        = @layout_class::KIND_CODES[code]
    notice_code = @layout_class::KIND_NOTICES[code]

    reader.note(notice_code, field: :kind, value: kind) if kind && notice_code

    kind
  end

  def entity(record)
    reference = record.cells[:reference].to_s.strip
    reference.empty? ? nil : "Client #{reference}"
  end

  def report_notice(record, notice)
    @report.add(level: notice.level, code: notice.code, source: source, line: record.line, entity: entity(record),
                field: notice.field, raw: notice.raw, value: notice.value, cells: record.cells)
  end

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
