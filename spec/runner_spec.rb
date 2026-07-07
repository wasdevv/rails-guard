RSpec.describe RailsGuard::Runner do
  def payload(command, cwd: RAILS_APP)
    {
      "tool_name" => "Bash",
      "hook_event_name" => "PreToolUse",
      "cwd" => cwd,
      "tool_input" => { "command" => command }
    }
  end

  it "asks for confirmation on a destructive command in a Rails project" do
    result = described_class.call(payload("bin/rails db:drop"))
    output = result["hookSpecificOutput"]

    expect(output["hookEventName"]).to eq("PreToolUse")
    expect(output["permissionDecision"]).to eq("ask")
    expect(output["permissionDecisionReason"]).to start_with("[rails-guard]")
    expect(output["permissionDecisionReason"]).to include("db:drop")
  end

  it "stays silent outside a Rails project" do
    Dir.mktmpdir do |dir|
      expect(described_class.call(payload("rails db:drop", cwd: dir))).to be_nil
    end
  end

  it "stays silent for safe commands" do
    expect(described_class.call(payload("bin/rails db:migrate"))).to be_nil
  end

  it "stays silent for non-Bash tools" do
    expect(described_class.call(payload("rails db:drop").merge("tool_name" => "Read"))).to be_nil
  end

  it "respects the RAILS_GUARD_DISABLE kill-switch" do
    ENV["RAILS_GUARD_DISABLE"] = "1"
    expect(described_class.call(payload("bin/rails db:drop"))).to be_nil
  ensure
    ENV.delete("RAILS_GUARD_DISABLE")
  end
end
