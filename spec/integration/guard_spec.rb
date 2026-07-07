require "json"
require "open3"

RSpec.describe "bin/guard" do
  BIN = File.expand_path("../../bin/guard", __dir__)

  def run_hook(payload, env = {})
    stdout, stderr, status = Open3.capture3(env, "ruby", BIN, stdin_data: payload.is_a?(String) ? payload : JSON.generate(payload))
    [stdout, stderr, status]
  end

  def payload(command, cwd: RAILS_APP)
    {
      "session_id" => "abc123",
      "hook_event_name" => "PreToolUse",
      "tool_name" => "Bash",
      "cwd" => cwd,
      "tool_input" => { "command" => command }
    }
  end

  it "emits an ask decision for a destructive command" do
    stdout, _, status = run_hook(payload("git pull && bin/rails db:reset"))

    expect(status.exitstatus).to eq(0)
    output = JSON.parse(stdout).fetch("hookSpecificOutput")
    expect(output["hookEventName"]).to eq("PreToolUse")
    expect(output["permissionDecision"]).to eq("ask")
    expect(output["permissionDecisionReason"]).to include("db:reset")
  end

  it "stays silent (exit 0, no stdout) for safe commands" do
    stdout, _, status = run_hook(payload("bundle exec rspec spec/models"))
    expect(status.exitstatus).to eq(0)
    expect(stdout).to be_empty
  end

  it "stays silent on invalid JSON stdin" do
    stdout, _, status = run_hook("not json at all {")
    expect(status.exitstatus).to eq(0)
    expect(stdout).to be_empty
  end

  it "respects the kill-switch" do
    stdout, _, status = run_hook(payload("bin/rails db:drop"), { "RAILS_GUARD_DISABLE" => "1" })
    expect(status.exitstatus).to eq(0)
    expect(stdout).to be_empty
  end
end
