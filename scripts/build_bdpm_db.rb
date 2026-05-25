#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Convertit la Base de Données Publique des Médicaments (BDPM,
# https://base-donnees-publique.medicaments.gouv.fr) en SQLite optimisée pour
# l'autocomplétion dans RettApp.
#
# Sources BDPM attendues (TSV ISO-8859-1) :
#   - CIS_bdpm.txt          (médicaments)
#   - CIS_COMPO_bdpm.txt    (compositions / substances actives)
#
# Le fichier de sortie `RettApp/Resources/bdpm.sqlite` contient une table
# `medications` indexée pour la recherche par préfixe (`name LIKE 'doli%'`).
#
# Usage :
#   ruby scripts/build_bdpm_db.rb                 # → fallback : seed depuis CommonFrenchMedications.swift
#   ruby scripts/build_bdpm_db.rb path/to/bdpm/   # → BDPM complet (dossier contenant les .txt)
#
# Refresh BDPM (manuel, périodique) :
#   1. Télécharger l'archive sur https://base-donnees-publique.medicaments.gouv.fr/telechargement.php
#   2. Décompresser dans un dossier
#   3. Lancer ce script en passant le dossier en argument
#   4. Re-générer l'xcodeproj : `ruby scripts/generate_xcodeproj.rb`
#   5. Rebuild l'app dans Xcode

require 'sqlite3'
require 'fileutils'

ROOT     = File.expand_path('..', __dir__)
OUT_PATH = File.join(ROOT, 'RettApp', 'Resources', 'bdpm.sqlite')
SEED_SRC = File.join(ROOT, 'RettApp', 'Shared', 'CommonFrenchMedications.swift')

# --- Schéma cible -----------------------------------------------------------
# Une seule table pour rester simple. Indexes pour autocomplete par préfixe.
SCHEMA = <<~SQL
  CREATE TABLE medications (
    cis             INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    name_lower      TEXT NOT NULL,
    short_name      TEXT,
    short_name_lower TEXT,
    dosage_form     TEXT,
    active_ingredient TEXT
  );
  CREATE INDEX idx_med_name_lower       ON medications (name_lower);
  CREATE INDEX idx_med_short_name_lower ON medications (short_name_lower);
SQL

# --- Sources alternatives ---------------------------------------------------

# Lit le fallback à partir de la liste curatée déjà dans le code.
# Permet d'avoir une SQLite non-vide même sans données BDPM téléchargées.
def seed_from_swift
  content = File.read(SEED_SRC, encoding: 'UTF-8')
  names = content.scan(/"([^"]+)"/).flatten
  rows = []
  names.each_with_index do |raw, i|
    # « Doliprane (paracétamol) » → name = "Doliprane (paracétamol)",
    # short_name = "Doliprane", active_ingredient = "paracétamol"
    short = raw.split('(').first.to_s.strip
    active = raw[/\(([^)]+)\)/, 1]
    rows << {
      cis: -(i + 1), # négatif → pas un CIS BDPM réel, sera remplacé en cas de refresh
      name: raw,
      short_name: short,
      dosage_form: nil,
      active_ingredient: active
    }
  end
  rows
end

# Lit `CIS_bdpm.txt` (médicaments) et `CIS_COMPO_bdpm.txt` (compositions),
# joint sur CIS, agrège les substances actives par CIS.
def seed_from_bdpm(dir)
  cis_path   = File.join(dir, 'CIS_bdpm.txt')
  compo_path = File.join(dir, 'CIS_COMPO_bdpm.txt')
  unless File.exist?(cis_path)
    abort "❌ #{cis_path} introuvable. Le dossier doit contenir les .txt BDPM."
  end

  # CIS_COMPO : CIS \t Désignation \t Code substance \t Dénomination substance \t Dosage \t Réf dosage \t Nature
  actives_by_cis = Hash.new { |h, k| h[k] = [] }
  if File.exist?(compo_path)
    File.foreach(compo_path, encoding: 'ISO-8859-1') do |line|
      cols = line.chomp.split("\t")
      next if cols.size < 4
      cis = cols[0].to_i
      next if cis.zero?
      actives_by_cis[cis] << cols[3].to_s.strip.downcase unless cols[3].to_s.empty?
    end
  end

  rows = []
  # CIS : CIS \t Dénomination \t Forme \t Voies \t Statut \t Type \t Etat commercialisation ...
  File.foreach(cis_path, encoding: 'ISO-8859-1') do |line|
    cols = line.chomp.split("\t")
    next if cols.size < 3
    cis = cols[0].to_i
    next if cis.zero?
    name = cols[1].to_s.strip
    next if name.empty?

    # « Doliprane 500 mg, comprimé pelliculé » → short = "Doliprane"
    short = name.split(/[, ]/).first

    # On exclut les médicaments retirés du marché (Etat commercialisation = "Arrêt de commercialisation").
    etat = cols.size > 6 ? cols[6].to_s.downcase : ''
    next if etat.include?('arrêt')

    actives = actives_by_cis[cis].uniq.first(3).join(', ')

    rows << {
      cis: cis,
      name: name,
      short_name: short,
      dosage_form: cols[2].to_s.strip,
      active_ingredient: actives.empty? ? nil : actives
    }
  end
  rows
end

# --- Génération SQLite ------------------------------------------------------

def build_db(rows)
  FileUtils.mkdir_p(File.dirname(OUT_PATH))
  FileUtils.rm_f(OUT_PATH)

  db = SQLite3::Database.new(OUT_PATH)
  db.execute_batch(SCHEMA)

  db.transaction do
    stmt = db.prepare(<<~SQL)
      INSERT OR REPLACE INTO medications
        (cis, name, name_lower, short_name, short_name_lower, dosage_form, active_ingredient)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    SQL
    rows.each do |r|
      stmt.execute(
        r[:cis],
        r[:name],
        r[:name].downcase,
        r[:short_name],
        r[:short_name]&.downcase,
        r[:dosage_form],
        r[:active_ingredient]
      )
    end
    stmt.close
  end

  # ANALYZE + VACUUM pour optimiser la taille et les plans de requête.
  db.execute('ANALYZE')
  db.execute('VACUUM')
  db.close
end

# --- Main -------------------------------------------------------------------

mode = ARGV[0]
rows = if mode && File.directory?(mode)
         puts "📂 Source BDPM : #{mode}"
         seed_from_bdpm(mode)
       else
         puts '📂 Pas de dossier BDPM fourni — seed depuis CommonFrenchMedications.swift'
         seed_from_swift
       end

build_db(rows)
size_kb = File.size(OUT_PATH) / 1024
puts "✅ #{OUT_PATH} généré (#{rows.size} médicaments, #{size_kb} KB)"
puts
puts 'Rappel : régénérer ensuite l\'xcodeproj pour que la SQLite soit incluse comme resource :'
puts '   ruby scripts/generate_xcodeproj.rb'
