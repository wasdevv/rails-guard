# frozen_string_literal: true

RSpec.describe RailsGuard::Runner do
  def payload(command, cwd: RAILS_APP)
    {
      'tool_name' => 'Bash',
      'hook_event_name' => 'PreToolUse',
      'cwd' => cwd,
      'tool_input' => { 'command' => command }
    }
  end

  # ---------------------------------------------------------------------------
  # ASK behaviour (existing, preserved)
  # ---------------------------------------------------------------------------

  it 'asks for confirmation on a destructive db:setup in a Rails project' do
    result = described_class.call(payload('bin/rails db:setup'))
    output = result['hookSpecificOutput']

    expect(output['hookEventName']).to eq('PreToolUse')
    expect(output['permissionDecision']).to eq('ask')
    expect(output['permissionDecisionReason']).to start_with('[rails-guard]')
    expect(output['permissionDecisionReason']).to include('db:setup')
  end

  it 'denies db:reset in a Rails project' do
    result = described_class.call(payload('bin/rails db:reset'))
    expect(result['hookSpecificOutput']['permissionDecision']).to eq('deny')
  end

  # ---------------------------------------------------------------------------
  # DENY behaviour (new)
  # ---------------------------------------------------------------------------

  it 'denies db:drop in a Rails project' do
    result = described_class.call(payload('bin/rails db:drop'))
    output = result['hookSpecificOutput']

    expect(output['permissionDecision']).to eq('deny')
    expect(output['permissionDecisionReason']).to start_with('[rails-guard]')
    expect(output['permissionDecisionReason']).to include('#rails-guard:allow')
  end

  it 'denies git push --force regardless of Rails project' do
    Dir.mktmpdir do |dir|
      result = described_class.call(payload('git push --force', cwd: dir))
      output = result['hookSpecificOutput']

      expect(output['permissionDecision']).to eq('deny')
    end
  end

  it 'denies git worktree remove --force outside a Rails project' do
    Dir.mktmpdir do |dir|
      result = described_class.call(payload('git worktree remove --force wt', cwd: dir))
      expect(result['hookSpecificOutput']['permissionDecision']).to eq('deny')
    end
  end

  # ---------------------------------------------------------------------------
  # Gate: Rails rules are silent outside a Rails project
  # ---------------------------------------------------------------------------

  it 'stays silent for db:drop outside a Rails project' do
    Dir.mktmpdir do |dir|
      expect(described_class.call(payload('bin/rails db:drop', cwd: dir))).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Inline bypass
  # ---------------------------------------------------------------------------

  it 'releases a deny when #rails-guard:allow is present in the command' do
    result = described_class.call(payload('bin/rails db:drop  #rails-guard:allow'))
    expect(result).to be_nil
  end

  # ---------------------------------------------------------------------------
  # Silent cases (unchanged)
  # ---------------------------------------------------------------------------

  it 'stays silent for safe commands' do
    expect(described_class.call(payload('bin/rails db:migrate'))).to be_nil
  end

  it 'stays silent for non-Bash tools' do
    expect(described_class.call(payload('rails db:drop').merge('tool_name' => 'Read'))).to be_nil
  end

  it 'respects the RAILS_GUARD_DISABLE kill-switch' do
    ENV['RAILS_GUARD_DISABLE'] = '1'
    expect(described_class.call(payload('bin/rails db:drop'))).to be_nil
  ensure
    ENV.delete('RAILS_GUARD_DISABLE')
  end

  # ---------------------------------------------------------------------------
  # A hyphen is not a word boundary you can trust
  # ---------------------------------------------------------------------------

  # `\\b(rails|rake)\\b` answered "yes, this invokes Rails" for the word inside
  # `rails-guard`, so prose naming this plugin was denied for mentioning a rake
  # task. The narrowing is the only one here that cannot turn a deny into a
  # pass for a command that would actually run: a hyphen-joined `rails` is
  # never the executable.
  it 'does not read the word inside rails-guard as a Rails invocation' do
    result = described_class.call(payload("gh pr create --body 'o rails-guard bloqueou db:drop'"))

    expect(result).to be_nil
  end

  it 'does not read rails_guard as a Rails invocation either' do
    expect(described_class.call(payload("echo 'rails_guard viu db:drop'"))).to be_nil
  end

  # Every shape a real invocation takes still has to be caught, because the two
  # errors do not cost the same: a false positive is an annoyance and a false
  # negative is a dropped database.
  ['bin/rails db:drop', './bin/rails db:drop', 'bundle exec rails db:drop', 'rake db:drop'].each do |command|
    it "still denies #{command}" do
      result = described_class.call(payload(command))

      expect(result.dig('hookSpecificOutput', 'permissionDecision')).to eq('deny')
    end
  end
end
