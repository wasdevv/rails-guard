# frozen_string_literal: true

require 'yaml'

module RailsGuard
  module Rules
    RAILS_OR_RAKE = /\b(rails|rake)\b/
    TEST_ENV = /RAILS_ENV=test\b|\bdb:test:|(-e|--environment)[= ]?test\b/
    WIPE = /delete_all|destroy_all|truncate|drop_table/i
    WORKTREE_PATH = %r{(~|/[^/]+)/\.swarm/worktrees/}
    INLINE_BYPASS = '#rails-guard:allow'

    # Each rule hash keys:
    #   :pattern       — Regexp that must match the command
    #   :decision      — "deny" | "ask"
    #   :requires_rails — true  → rule is skipped when cwd is not a Rails project
    #                     false → rule fires in any cwd
    #   :requires      — optional Regexp that must ALSO match (e.g. rails|rake guard)
    #   :unless        — optional Regexp that suppresses the rule when matched
    #   :extra         — optional Regexp that must ALSO match (second content guard)
    #   :reason        — String with optional %s (filled from matched fragment)
    BUILT_IN = [
      # -----------------------------------------------------------------------
      # DENY — irrecoverable (Rails-scoped)
      # -----------------------------------------------------------------------
      {
        pattern: /\bdb:(drop|reset|schema:load)\b/,
        decision: 'deny',
        requires_rails: true,
        requires: RAILS_OR_RAKE,
        unless: TEST_ENV,
        reason: '%s drops or overwrites the database schema — this is irrecoverable. ' \
                'If you need to reset only test data use db:test:prepare. ' \
                'To proceed intentionally, append #rails-guard:allow to the command.'
      },
      # -----------------------------------------------------------------------
      # ASK — recoverable / reversible (Rails-scoped)
      # -----------------------------------------------------------------------
      {
        pattern: /\bdb:(migrate:reset|setup|seed:replant|fixtures:load)\b/,
        decision: 'ask',
        requires_rails: true,
        requires: RAILS_OR_RAKE,
        unless: TEST_ENV,
        reason: '%s rewrites or destroys database data'
      },
      {
        pattern: /\brails\s+(destroy|d)\s+\w/,
        decision: 'ask',
        requires_rails: true,
        reason: 'rails destroy deletes generated files'
      },
      {
        pattern: /\brails\s+(runner|r)\s+\S/,
        decision: 'ask',
        requires_rails: true,
        extra: WIPE,
        unless: TEST_ENV,
        reason: 'this rails runner call wipes records (%s)'
      },
      # -----------------------------------------------------------------------
      # DENY — irrecoverable (any cwd)
      # -----------------------------------------------------------------------
      {
        pattern: /\brm\s+(-\w*r\w*f|-\w*f\w*r)\s+\S/,
        decision: 'deny',
        requires_rails: false,
        extra: WORKTREE_PATH,
        reason: 'rm -rf on a swarm worktree permanently deletes all uncommitted work ' \
                "and the agent's conversation history for that task — irrecoverable. " \
                'Use the Swarm UI (Discard button) to clean up safely. ' \
                'To proceed intentionally, append #rails-guard:allow to the command.'
      },
      {
        pattern: /\bgit\s+worktree\s+remove\s+--force\b/,
        decision: 'deny',
        requires_rails: false,
        reason: 'git worktree remove --force deletes the worktree directory including all ' \
                'uncommitted changes — irrecoverable. ' \
                'Use the Swarm UI (Discard button) instead. ' \
                'To proceed intentionally, append #rails-guard:allow to the command.'
      },
      {
        # Match --force or -f but NOT --force-with-lease
        pattern: /\bgit\s+push\b(?=.*\s(--force|-f)\b)(?!.*--force-with-lease)/,
        decision: 'deny',
        requires_rails: false,
        reason: 'git push --force rewrites remote history and is irrecoverable for anyone ' \
                'who has already fetched. Use --force-with-lease instead: it only pushes if ' \
                'the remote tip matches your local expectation, preventing accidental overwrites. ' \
                'To proceed intentionally, append #rails-guard:allow to the command.'
      },
      {
        pattern: %r{\bgit\s+reset\s+--hard\s+(origin/)?(main|master)\b},
        decision: 'deny',
        requires_rails: false,
        reason: 'git reset --hard main/master discards all local commits on your default branch ' \
                'that have not been pushed — irrecoverable without a reflog rescue. ' \
                'If you want to align with the remote, use git fetch && git reset --hard origin/main instead ' \
                '(and only when you are sure there is nothing worth keeping). ' \
                'To proceed intentionally, append #rails-guard:allow to the command.'
      }
    ].freeze

    # Returns {decision:, reason:} or nil.
    def self.decision(command, cwd)
      config = load_config(cwd)
      return nil if command.include?(INLINE_BYPASS)
      return nil if Array(config['allow']).any? { |p| regexp(p)&.match?(command) }

      is_rails = RailsGuard::Runner.rails_project?(cwd)

      (BUILT_IN + custom_rules(config)).each do |rule|
        next if rule.fetch(:requires_rails, true) && !is_rails
        next unless command.match?(rule[:pattern])
        next if rule[:requires] && !command.match?(rule[:requires])
        next if rule[:unless] && command.match?(rule[:unless])
        next if rule[:extra] && !command.match?(rule[:extra])

        fragment = command[rule[:extra] || rule[:pattern]]
        reason = rule[:reason].include?('%s') ? format(rule[:reason], fragment) : rule[:reason]
        return { decision: rule.fetch(:decision, 'ask'), reason: reason }
      end

      nil
    end

    # Legacy API — returns reason string or nil (kept for backward compatibility).
    def self.match(command, cwd)
      result = decision(command, cwd)
      result&.fetch(:reason)
    end

    def self.custom_rules(config)
      Array(config['ask']).filter_map do |entry|
        next unless entry.is_a?(Hash)

        pattern = regexp(entry['pattern']) or next
        {
          pattern: pattern,
          decision: 'ask',
          requires_rails: false,
          reason: entry['reason'].to_s.empty? ? 'matches a custom rails-guard rule' : entry['reason']
        }
      end
    end

    def self.load_config(cwd)
      path = File.join(cwd.to_s, '.rails-guard.yml')
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
