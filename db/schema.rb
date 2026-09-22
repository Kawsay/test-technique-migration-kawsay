ActiveRecord::Schema.define do
  enable_extension "plpgsql"

  create_table :customers, force: :cascade do |t|
    t.string  :reference, null: false          # code du client dans CaveGest
    t.string  :company_name
    t.string  :first_name
    t.string  :last_name
    t.string  :address1
    t.string  :city
    t.string  :zip
    t.string  :country_code, limit: 2
    t.string  :phone
    t.string  :mobile
    t.string  :email
    t.string  :kind, null: false, default: "customer"  # customer / supplier / prospect
    t.string  :customer_category
    t.string  :price_grid_code
    t.string  :vat_number
    t.string  :excise_number
    t.date    :creation_date
    t.boolean :active, null: false, default: true

    t.boolean :use_billing_address, null: false, default: true
    t.string  :shipping_company_name
    t.string  :shipping_first_name
    t.string  :shipping_last_name
    t.string  :shipping_address1
    t.string  :shipping_city
    t.string  :shipping_zip
    t.string  :shipping_country_code, limit: 2
    t.string  :shipping_phone

    t.timestamps

    t.index :reference, unique: true
    t.index :vat_number
    t.index :price_grid_code
  end

  create_table :products, force: :cascade do |t|
    t.string  :reference, null: false
    t.string  :name, null: false
    t.string  :vintage
    t.string  :color                        # voir Product::WINE_COLORS
    t.string  :appellation                  # voir Product::APPELLATIONS
    t.string  :product_type                 # voir Product::PRODUCT_TYPES
    t.string  :container_label              # contenant tel qu'écrit dans le logiciel d'origine
    t.string  :container_type               # voir Product::CONTAINER_TYPES
    t.integer :units_per_container          # nombre d'unités dans le contenant
    t.integer :volume_ml                    # volume d'une unité
    t.decimal :vat_rate, precision: 5, scale: 2
    t.integer :stock
    t.timestamps

    t.index :reference, unique: true
  end

  create_table :product_prices, force: :cascade do |t|
    t.references :product, null: false, foreign_key: true
    t.string     :grid_code, null: false
    t.decimal    :amount_ht, precision: 10, scale: 2, null: false
    t.timestamps

    t.index %i[product_id grid_code], unique: true
  end
end
