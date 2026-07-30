# frozen_string_literal: true

module RailsGuard
  class Runner
    def self.call(payload)
      return nil if ENV['RAILS_GUARD_DISABLE'] == '1'
      return nil unless payload.is_a?(Hash)
      return nil unless payload['tool_name'] == 'Bash'

      command = payload.dig('tool_input', 'command').to_s
      cwd = payload['cwd'].to_s
      return nil if command.empty?

      # Rules.decision handles the per-rule requires_rails gate internally;
      # we no longer short-circuit the whole hook on rails_project? here so
      # that non-Rails rules (git push --force, rm -rf worktree, etc.) can
      # fire regardless of cwd.
      result = Rules.decision(command, cwd) or return nil

      {
        'hookSpecificOutput' => {
          'hookEventName' => 'PreToolUse',
          'permissionDecision' => result[:decision],
          'permissionDecisionReason' => "[rails-guard] #{result[:reason]}"
        }
      }
    end

    def self.rails_project?(cwd)
      return false if cwd.empty?

      File.file?(File.join(cwd, 'bin', 'rails')) || File.file?(File.join(cwd, 'config', 'application.rb'))
    end
  end
end
