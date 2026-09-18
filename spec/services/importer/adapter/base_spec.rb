require "spec_helper"

RSpec.describe Importer::Adapter::Base do
  it "requires subclasses to implement the reading of their format" do
    adapter = Class.new(described_class).new("produits.txt")

    expect { adapter.rows }.to raise_error(NotImplementedError, /must implement #read_rows/)
  end

  it "exposes the name of the file, without its directory" do
    adapter = Class.new(described_class).new(File.join("data", "clients", "produits.txt"))

    expect(adapter.file_name).to eq("produits.txt")
  end

  # Adaptateur minimal
  context "with a subclass reading its format" do
    let(:adapter_class) do
      Class.new(described_class) do
        private

        def read_rows
          rows = {}
          File.readlines(@path, chomp: true).each_with_index do |text, index|
            rows[index + 1] = text.split(",")
          end
          rows
        end
      end
    end

    def file_with(rows)
      path = File.join(Dir.mktmpdir, "produits.txt")
      File.write(path, rows.map { |values| values.join(",") }.join("\n"))
      adapter_class.new(path)
    end

    it_behaves_like "an adapter"
  end
end
