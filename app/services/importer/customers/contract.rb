# Règles métier qu'un client doit respecter pour être repris, quel que soit le logiciel source.
#
# Le schéma ne fait que vérifier les types ; il accepte nil partout (maybe), car une valeur absente
# n'est pas une erreur de type. Ce sont les règles qui décident du rejet, et chacune porte son code
# (meta[:code]), qui identifie l'anomalie dans le rapport.
class Importer::Customers::Contract < Dry::Validation::Contract
  schema do
    required(:reference).maybe(:string)
    required(:kind).maybe(:string)
    required(:company_name).maybe(:string)
    required(:first_name).maybe(:string)
    required(:last_name).maybe(:string)
  end

  rule(:reference) do
    key.failure(text: "reference missing", code: :reference_missing) if value.nil?
  end

  rule(:kind) do
    key.failure(text: "unknown kind", code: :kind_unknown) unless Customer::KINDS.include?(value)
  end

  rule(:company_name, :first_name, :last_name) do
    if values[:company_name].nil? && values[:first_name].nil? && values[:last_name].nil?
      base.failure(text: "neither company name, first name nor last name", code: :name_missing)
    end
  end
end
