# Mise en forme de la sortie console. Les couleurs ne sont écrites que si la sortie est un terminal :
# redirigée dans un fichier, ou avec NO_COLOR, la sortie reste du texte brut.
module Importer::Console
  STYLES = { bold: 1, dim: 2, red: 31, green: 32, yellow: 33 }.freeze

  WIDTH = 78

  def self.colors?
    $stdout.tty? && ENV["NO_COLOR"].nil?
  end

  def self.paint(text, *styles)
    return text.to_s unless colors?

    "#{styles.map { |style| "\e[#{STYLES.fetch(style)}m" }.join}#{text}\e[0m"
  end

  # Titre d'une étape, précédé d'une ligne vide : les étapes se distinguent d'un coup d'œil.
  def self.title(text)
    "\n#{paint("── #{text} ".ljust(WIDTH, "─"), :bold)}"
  end
end
