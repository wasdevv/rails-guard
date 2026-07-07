module RailsGuard
  class Runner
    def self.call(payload)
      return nil if ENV["RAILS_GUARD_DISABLE"] == "1"
      return nil unless payload.is_a?(Hash)
      return nil unless payload["tool_name"] == "Bash"

      command = payload.dig("tool_input", "command").to_s
      cwd = payload["cwd"].to_s
      return nil if command.empty?
      return nil unless rails_project?(cwd)

      reason = Rules.match(command, cwd) or return nil

      {
        "hookSpecificOutput" => {
          "hookEventName" => "PreToolUse",
          "permissionDecision" => "ask",
          "permissionDecisionReason" => "[rails-guard] #{reason}"
        }
      }
    end

    def self.rails_project?(cwd)
      return false if cwd.empty?

      File.file?(File.join(cwd, "bin", "rails")) || File.file?(File.join(cwd, "config", "application.rb"))
    end
  end
end
