# Écrit en base les produits et les tarifs préparés par Importer::ProductPrices::Prepare, sans jamais créer
# de doublon.
#
# Les produits puis leurs tarifs sont écrits dans une même transaction : un produit n'est jamais écrit sans
# ses tarifs. L'écriture est idempotente (voir Importer::Writer) : rejouer l'import sur le même fichier ne
# modifie aucune ligne.
#
# Un tarif en base dont la grille est vide dans le fichier est retiré. Les produits absents du fichier, et
# leurs tarifs, ne sont pas modifiés.
#
# accepted - Array des Importer::ProductPrices::Prepare::Accepted à écrire.
# source   - nom du fichier d'origine, pour le rapport.
# report   - MigrationReport.
class Importer::ProductPrices::Upsert
  # Clé naturelle : la référence du produit dans le logiciel source (index unique en base).
  KEY = :reference

  # Un tarif par produit et par grille (index unique en base).
  PRICE_KEY = %i[product_id grid_code].freeze

  def initialize(accepted:, source:, report:)
    @accepted = accepted
    @source   = source
    @report   = report
  end

  def call
    accepted = without_duplicates

    products_bilan, prices_bilan, removed_prices = Product.transaction do
      products_bilan = write_products(accepted)
      product_ids    = product_ids_of(accepted)

      [products_bilan, write_prices(accepted, product_ids), remove_emptied_prices(accepted, product_ids)]
    end

    @report.record_bilan(@source, :products, products_bilan)
    @report.record_bilan(@source, :product_prices, prices_bilan)
    removed_prices.each { |candidate, price| report_removal(candidate, price) }
  end

  private

  # Une référence présente plusieurs fois n'est reprise sous aucune de ses versions : rien ne permet
  # de choisir laquelle est la bonne, et l'ordre de lecture ne doit pas en décider à notre place.
  def without_duplicates
    kept, duplicated = @accepted.group_by { |accepted| accepted.product[KEY] }.partition do |_reference, group|
      group.size == 1
    end

    duplicated.each { |_reference, group| report_duplicates(group) }

    kept.flat_map { |_reference, group| group }
  end

  def report_duplicates(group)
    # Les lignes d'une même référence portent-elles toutes le même produit, aux mêmes prix ?
    identical = group.map { |accepted| [accepted.product, accepted.prices] }.uniq.one?
    code      = identical ? :duplicate_identical : :duplicate_conflict
    lines     = group.map { |accepted| accepted.record.line }

    group.each do |accepted|
      @report.add(level: :rejected, code: code, source: @source, line: accepted.record.line,
                  entity: entity(accepted), field: KEY, raw: accepted.product[KEY], value: lines.join(", "),
                  cells: accepted.record.cells)
    end
  end

  def write_products(accepted)
    writer = Importer::Writer.new(model: Product, key: [KEY], columns: Importer::ProductPrices::PRODUCT_ATTRIBUTES)

    writer.call(accepted.map { |candidate| candidate.product })
  end

  # Référence => id, pour les produits qui viennent d'être écrits.
  def product_ids_of(accepted)
    Product.where(KEY => accepted.map { |candidate| candidate.product[KEY] }).pluck(KEY, :id).to_h
  end

  def write_prices(accepted, product_ids)
    writer = Importer::Writer.new(model: ProductPrice, key: PRICE_KEY, columns: Importer::ProductPrices::PRICE_ATTRIBUTES)
    rows   = accepted.flat_map do |candidate|
      product_id = product_ids.fetch(candidate.product[KEY])

      candidate.prices.map { |price| price.merge(product_id: product_id) }
    end

    writer.call(rows)
  end

  # Un tarif en base dont la grille est vide dans le fichier est retiré : le client l'a supprimé depuis
  # l'import précédent. Une grille illisible, elle, ne retire rien : c'est la lecture qui a échoué.
  #
  # Renvoie les tarifs retirés : Array de [Accepted, ProductPrice].
  def remove_emptied_prices(accepted, product_ids)
    accepted_by_id = accepted.index_by { |candidate| product_ids.fetch(candidate.product[KEY]) }

    removed = ProductPrice.where(product_id: accepted_by_id.keys).to_a.filter_map do |price|
      candidate = accepted_by_id.fetch(price.product_id)
      [candidate, price] if candidate.empty_grids.include?(price.grid_code)
    end

    ProductPrice.where(id: removed.map { |_candidate, price| price.id }).delete_all
    removed
  end

  # value : montant retiré de la base.
  def report_removal(candidate, price)
    @report.add(level: :info, code: :price_removed, source: @source, line: candidate.record.line,
                entity: "#{entity(candidate)}, grille #{price.grid_code}", field: :amount_ht,
                value: price.amount_ht, cells: candidate.record.cells)
  end

  def entity(accepted)
    "Produit #{accepted.product[KEY]}"
  end
end
