#!/usr/bin/env ruby
# Converts the native MT5 SpreadsheetML optimization report to CSV.
# It does not calculate or simulate any trading result.

require "csv"
require "rexml/document"

abort "usage: #{$PROGRAM_NAME} REPORT.xml [ROW_LIMIT]" unless (1..2).cover?(ARGV.length)

document = REXML::Document.new(File.binread(ARGV.fetch(0)))
rows = []
REXML::XPath.each(document, "//*[local-name()='Table']/*[local-name()='Row']") do |row|
  values = []
  row.elements.each do |cell|
    next unless cell.name == "Cell"

    index_attribute = cell.attributes["ss:Index"] || cell.attributes["Index"]
    target_index = index_attribute ? index_attribute.to_i - 1 : values.length
    values << nil while values.length < target_index
    data = cell.elements.find { |element| element.name == "Data" }
    values << (data&.text || "")
  end
  rows << values
end

limit = ARGV[1]&.to_i
rows = rows.first(limit + 1) if limit&.positive?
rows.each { |row| puts CSV.generate_line(row) }
