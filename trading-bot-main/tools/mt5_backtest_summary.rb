#!/usr/bin/env ruby
# Extracts headline metrics from native MT5 detailed HTML reports.

require "cgi"
require "csv"

abort "usage: #{$PROGRAM_NAME} REPORT.htm [REPORT.htm ...]" if ARGV.empty?

labels = {
  "History Quality" => "Qualità dello Storico:",
  "Bars" => "Barre:",
  "Ticks" => "Ticks:",
  "Net Profit" => "Profitto Totale Netto:",
  "Profit Factor" => "Fattore di Profitto:",
  "Expected Payoff" => "Payoff Atteso:",
  "Equity DD Relative" => "Equità Drawdown Relativa:",
  "Sharpe" => "Indice di Sharpe:",
  "Trades" => "Numero di Operazioni di Trading Totali:",
  "Short Trades" => "Operazioni di Trading Short (vincenti %):",
  "Long Trades" => "Operazioni di Trading Long (vincenti %):"
}.freeze

puts CSV.generate_line(["Report"] + labels.keys)
ARGV.each do |path|
  raw = File.binread(path)
  html = if raw.start_with?("\xFF\xFE".b)
           raw.byteslice(2..).force_encoding("UTF-16LE").encode("UTF-8")
         else
           raw.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
         end
  cells = html.scan(/<td\b[^>]*>(.*?)<\/td>/mi).flatten.map do |cell|
    CGI.unescapeHTML(cell.gsub(/<[^>]+>/, "").gsub(/\s+/, " ").strip)
  end
  values = labels.values.map do |label|
    index = cells.index(label)
    index ? cells[(index + 1)..].find { |value| !value.empty? } : ""
  end
  puts CSV.generate_line([File.basename(path)] + values)
end
