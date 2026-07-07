require "yaml"

module RailsGuard
  module Rules
    RAILS_OR_RAKE = /\b(rails|rake)\b/
    TEST_ENV = /RAILS_ENV=test\b|\bdb:test:|(-e|--environment)[= ]?test\b/
    WIPE = /delete_all|destroy_all|truncate|drop_table/i

    BUILT_IN = [
      { pattern: /\bdb:(drop|reset|migrate:reset|schema:load|setup|seed:replant|fixtures:load)\b/,
        requires: RAILS_OR_RAKE,
        unless: TEST_ENV,
        reason: "%s rewrites or destroys database data" },
      { pattern: /\brails\s+(destroy|d)\s+\w/,
        reason: "rails destroy deletes generated files" },
      { pattern: /\brails\s+(runner|r)\s+\S/,
        extra: WIPE,
        unless: TEST_ENV,
        reason: "this rails runner call wipes records (%s)" }
    ].freeze

    def self.match(command, cwd)
      config = load_config(cwd)
      return nil if Array(config["allow"]).any? { |p| regexp(p)&.match?(command) }

      (BUILT_IN + custom_rules(config)).each do |rule|
        next unless command.match?(rule[:pattern])
        next if rule[:requires] && !command.match?(rule[:requires])
        next if rule[:unless] && command.match?(rule[:unless])
        next if rule[:extra] && !command.match?(rule[:extra])

        fragment = command[rule[:extra] || rule[:pattern]]
        return rule[:reason].include?("%s") ? format(rule[:reason], fragment) : rule[:reason]
      end

      nil
    end

    def self.custom_rules(config)
      Array(config["ask"]).filter_map do |entry|
        next unless entry.is_a?(Hash)

        pattern = regexp(entry["pattern"]) or next
        { pattern: pattern, reason: entry["reason"].to_s.empty? ? "matches a custom rails-guard rule" : entry["reason"] }
      end
    end

    def self.load_config(cwd)
      path = File.join(cwd.to_s, ".rails-guard.yml")
      return {} unless File.file?(path)

      YAML.safe_load(File.read(path)) || {}
    rescue StandardError
      {}
    end

    def self.regexp(source)
      Regexp.new(source.to_s)
    rescue RegexpError
      nil
    end
  end
end
