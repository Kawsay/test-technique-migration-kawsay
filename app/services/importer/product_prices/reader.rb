# Lit les cellules d'une ligne de produit avec les parsers, et retient les événements rencontrés.
class Importer::ProductPrices::Reader < Importer::Reader
  LEVELS_BY_CODE = {
    # Tarifs non repris : le produit l'est, mais pas ce prix.
    amount_invalid:           :rejected,
    amount_not_positive:      :rejected,

    # Valeurs corrigées : le client valide la règle appliquée.
    price_ttc_converted:      :repaired,
    container_read_as_case:   :repaired,

    # Valeurs reprises mais douteuses, ou vidées car illisibles : le client vérifie.
    price_grids_inconsistent:        :suspect,
    container_missing:               :suspect,
    color_inconsistent_with_section: :suspect,
    container_volume_missing: :suspect,
    container_invalid:        :suspect,
    color_unknown:            :suspect,
    section_unknown:          :suspect,
    vat_rate_invalid:         :suspect,
    vat_rate_unknown:         :suspect,
    integer_invalid:          :suspect,

    # Transformations attendues, ou valeur absente sans effet sur la vente : rien à faire.
    color_missing:            :info,
    price_grid_empty:         :info
  }.freeze

  # Champ du Product => cellule d'où il est lu, quand leurs noms diffèrent.
  CELLS_BY_FIELD = { container_label: :container }.freeze

  def money(field)
    read(field, Importer::Parsers.money(cell(field)))
  end

  def vat_rate(field)
    read(field, Importer::Parsers.vat_rate(cell(field)))
  end

  def integer(field)
    read(field, Importer::Parsers.integer(cell(field)))
  end

  def color(field)
    read(field, Importer::Parsers.term(cell(field), terms: @layout_class::COLORS, failure: :color_unknown))
  end

  # Contenant : Hash { type:, units:, volume_ml: }, ou nil.
  def container(field)
    read(field, Importer::Parsers.container(cell(field),
                                            types: @layout_class::CONTAINER_TYPES,
                                            case_type: @layout_class::CASE_CONTAINER_TYPE,
                                            volume_unit_ml: @layout_class::CONTAINER_VOLUME_UNIT_ML))
  end
end
