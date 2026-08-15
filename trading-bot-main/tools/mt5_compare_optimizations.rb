#!/usr/bin/env ruby
# Joins two native MT5 optimization reports by their optimized inputs.
# Ranking remains based on the first (development) report; the second is a gate.

require "csv"
require "rexml/document"

abort "usage: #{$PROGRAM_NAME} DEVELOPMENT.xml VALIDATION.xml [ROW_LIMIT]" unless (2..3).cover?(ARGV.length)

def report_rows(path)
  document = REXML::Document.new(File.binread(path))
  matrix = []
  REXML::XPath.each(document, "//*[local-name()='Table']/*[local-name()='Row']") do |row|
    values = row.elements.filter_map do |cell|
      next unless cell.name == "Cell"

      data = cell.elements.find { |element| element.name == "Data" }
      data&.text || ""
    end
    matrix << values
  end
  header = matrix.shift
  matrix.map { |values| header.zip(values).to_h }
end

development = report_rows(ARGV.fetch(0))
validation = report_rows(ARGV.fetch(1))
abort "empty report" if development.empty? || validation.empty?
minimum_development_trades = ENV.fetch("MT5_MIN_DEV_TRADES", "12").to_i
minimum_validation_trades = ENV.fetch("MT5_MIN_VAL_TRADES", "4").to_i

parameters = development.first.keys.grep(/^Inp/).select { |name| validation.first.key?(name) }
key_for = ->(row) { parameters.map { |name| row.fetch(name, "") }.join("\u001f") }
validation_by_key = validation.to_h { |row| [key_for.call(row), row] }

joined = development.filter_map do |dev|
  val = validation_by_key[key_for.call(dev)]
  next unless val
  next unless dev.fetch("Profit").to_f.positive? && val.fetch("Profit").to_f.positive?
  next unless dev.fetch("Profit Factor").to_f > 1.0 && val.fetch("Profit Factor").to_f > 1.0
  next unless dev.fetch("Trades").to_i >= minimum_development_trades
  next unless val.fetch("Trades").to_i >= minimum_validation_trades

  [dev, val]
end
joined.sort_by! { |dev, _val| -dev.fetch("Result").to_f }

metric_names = ["Profit", "Profit Factor", "Equity DD %", "Trades", "Sharpe Ratio"]
header = parameters + metric_names.map { |name| "Dev #{name}" } + metric_names.map { |name| "Val #{name}" }
puts CSV.generate_line(header)
limit = ARGV[2]&.to_i
(limit&.positive? ? joined.first(limit) : joined).each do |dev, val|
  values = parameters.map { |name| dev.fetch(name) }
  values.concat(metric_names.map { |name| dev.fetch(name) })
  values.concat(metric_names.map { |name| val.fetch(name) })
  puts CSV.generate_line(values)
end
