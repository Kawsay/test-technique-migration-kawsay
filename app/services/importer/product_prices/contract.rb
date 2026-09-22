# Règles métier qu'un produit doit respecter pour être repris, quel que soit le logiciel source.
#
# Le schéma ne fait que vérifier les types ; il accepte nil partout (maybe), car une valeur absente
# n'est pas une erreur de type. Ce sont les règles qui décident du rejet, et chacune porte son code
# (meta[:code]), qui identifie l'anomalie dans le rapport.
class Importer::ProductPrices::Contract < Dry::Validation::Contract
  schema do
    required(:reference).maybe(:string)
    required(:name).maybe(:string)
    required(:vat_rate).maybe(:decimal)
  end

  rule(:reference) do
    key.failure(text: "reference missing", code: :reference_missing) if value.nil?
  end

  rule(:name) do
    key.failure(text: "name missing", code: :name_missing) if value.nil?
  end

  # Sans taux de TVA, les prix saisis TTC ne peuvent pas être convertis en HT.
  rule(:vat_rate) do
    key.failure(text: "vat rate missing", code: :vat_rate_missing) if value.nil?
  end
end
