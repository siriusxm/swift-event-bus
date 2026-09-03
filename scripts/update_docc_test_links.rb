#!/usr/bin/env ruby

require "uri"

repository_root = File.expand_path("..", __dir__)
documentation_paths = Dir.glob(
  File.join(repository_root, "Sources/EventBus/Documentation.docc/**/*.md")
).sort
documentation_paths << File.join(repository_root, "README.md")
check_only = ARGV.include?("--check")

link_pattern = %r{
  \[([A-Za-z_][A-Za-z0-9_]*\(\))\]
  \(https://github\.com/siriusxm/swift-event-bus/blob/main/
  (Tests/[^)#]+\.swift)\#L(\d+)\)
}x

updates = []

documentation_paths.each do |documentation_path|
  original = File.read(documentation_path)
  revised = original.gsub(link_pattern) do
    label = Regexp.last_match(1)
    encoded_source_path = Regexp.last_match(2)
    current_line = Regexp.last_match(3).to_i
    method_name = label.delete_suffix("()")
    source_path = File.join(repository_root, URI::DEFAULT_PARSER.unescape(encoded_source_path))

    abort "Missing linked test source: #{source_path}" unless File.file?(source_path)

    source_lines = File.readlines(source_path)
    matching_lines = source_lines.each_index.select do |index|
      source_lines[index].match?(/\bfunc\s+#{Regexp.escape(method_name)}\s*\(/)
    end

    unless matching_lines.one?
      abort "Expected one declaration of #{method_name} in #{source_path}, found #{matching_lines.count}"
    end

    updated_line = matching_lines.first + 1
    updates << [documentation_path, label, current_line, updated_line] if updated_line != current_line

    "[#{label}](https://github.com/siriusxm/swift-event-bus/blob/main/#{encoded_source_path}#L#{updated_line})"
  end

  File.write(documentation_path, revised) if !check_only && revised != original
end

if updates.empty?
  puts "Documentation test link anchors are current."
  exit 0
end

updates.each do |documentation_path, label, current_line, updated_line|
  relative_path = documentation_path.delete_prefix("#{repository_root}/")
  puts "#{relative_path}: #{label} L#{current_line} -> L#{updated_line}"
end

if check_only
  warn "Documentation test link anchors are stale. Run: ruby scripts/update_docc_test_links.rb"
  exit 1
end

puts "Updated #{updates.count} DocC test link anchor#{updates.count == 1 ? '' : 's'}."
