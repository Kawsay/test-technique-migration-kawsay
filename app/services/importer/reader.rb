# Lit les cellules d'une ligne avec les parsers, et retient les événements rencontrés.
#
# Trois étapes s'enchaînent pour chaque cellule :
# 1. normalisation propre au logiciel source : un marqueur de valeur absente ("N/C") devient une cellule vide ;
# 2. lecture par le parser du champ, avec les conventions du logiciel (format de date, pays par défaut…) ;
# 3. mémorisation de l'événement éventuel : correction appliquée, valeur douteuse ou valeur illisible.
#
# La valeur brute reste celle saisie par le client, avant normalisation : c'est elle qui figure dans le rapport.
#
# Une sous-classe par type d'enregistrement importé (clients, produits…) déclare :
# - LEVELS_BY_CODE : la gravité de chaque événement qu'elle peut rencontrer ;
# - CELLS_BY_FIELD : la cellule d'où un champ est lu, quand leurs noms diffèrent (aucune par défaut).
class Importer::Reader
  Notice = Data.define(:level, :code, :field, :raw, :value)

  CELLS_BY_FIELD = {}.freeze

  attr_reader :notices

  # record       - Importer::Layout::Base::Record à lire.
  # layout_class - disposition de l'export, qui déclare les conventions de saisie du logiciel.
  def initialize(record:, layout_class:)
    @record       = record
    @layout_class = layout_class
    @notices      = []
  end

  def text(field)
    read(field, Importer::Parsers.text(cell(field)))
  end

  def label(field)
    read(field, Importer::Parsers.label(cell(field)))
  end

  def date(field)
    read(field, Importer::Parsers.date(cell(field), format: @layout_class::DATE_FORMAT))
  end

  def flag(field)
    read(field, Importer::Parsers.flag(cell(field),
                                       true_values: @layout_class::FLAG_TRUE_VALUES,
                                       false_values: @layout_class::FLAG_FALSE_VALUES))
  end

  # Valeur brute d'un champ, telle que saisie par le client.
  def raw(field)
    @record.cells[self.class::CELLS_BY_FIELD.fetch(field, field)]
  end

  # La cellule d'un champ est-elle vide, une fois les marqueurs de valeur absente écartés ?
  def empty_cell?(field)
    cell(field).to_s.strip.empty?
  end

  # raw - valeur brute à rapporter, celle de la cellule du champ par défaut.
  def note(code, field:, value:, raw: raw(field))
    level = self.class::LEVELS_BY_CODE.fetch(code)

    @notices << Notice.new(level: level, code: code, field: field, raw: raw, value: value)
  end

  private

  # Valeur normalisée d'un champ : les marqueurs de valeur absente du logiciel source sont des cellules vides.
  def cell(field)
    value = raw(field)

    @layout_class::EMPTY_MARKERS.include?(value) ? nil : value
  end

  # Une valeur illisible vide le champ ; une correction ou un doute est noté.
  def read(field, result)
    if result.failure?
      note(result.failure, field: field, value: nil)
      return nil
    end

    parsed = result.value!
    note(parsed.notice, field: field, value: parsed.value) if parsed.notice

    parsed.value
  end
end
