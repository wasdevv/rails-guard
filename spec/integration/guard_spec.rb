# frozen_string_literal: true

require 'json'
require 'open3'

RSpec.describe 'bin/guard' do
  BIN = File.expand_path('../../bin/guard', __dir__)

  def run_hook(payload, env = {})
    stdout, stderr, status = Open3.capture3(env, 'ruby', BIN,
                                            stdin_data: payload.is_a?(String) ? payload : JSON.generate(payload))
    [stdout, stderr, status]
  end

  def payload(command, cwd: RAILS_APP)
    {
      'session_id' => 'abc123',
      'hook_event_name' => 'PreToolUse',
      'tool_name' => 'Bash',
      'cwd' => cwd,
      'tool_input' => { 'command' => command }
    }
  end

  it 'emits an ask decision for db:setup' do
    stdout, _, status = run_hook(payload('git pull && bin/rails db:setup'))

    expect(status.exitstatus).to eq(0)
    output = JSON.parse(stdout).fetch('hookSpecificOutput')
    expect(output['hookEventName']).to eq('PreToolUse')
    expect(output['permissionDecision']).to eq('ask')
    expect(output['permissionDecisionReason']).to include('db:setup')
  end

  it 'emits a deny decision for db:reset' do
    stdout, _, status = run_hook(payload('git pull && bin/rails db:reset'))

    expect(status.exitstatus).to eq(0)
    output = JSON.parse(stdout).fetch('hookSpecificOutput')
    expect(output['permissionDecision']).to eq('deny')
    expect(output['permissionDecisionReason']).to include('#rails-guard:allow')
  end

  it 'emits a deny decision for db:drop' do
    stdout, _, status = run_hook(payload('bin/rails db:drop'))

    expect(status.exitstatus).to eq(0)
    output = JSON.parse(stdout).fetch('hookSpecificOutput')
    expect(output['permissionDecision']).to eq('deny')
    expect(output['permissionDecisionReason']).to include('[rails-guard]')
    expect(output['permissionDecisionReason']).to include('#rails-guard:allow')
  end

  it 'emits a deny decision for git push --force outside a Rails project' do
    Dir.mktmpdir do |dir|
      stdout, _, status = run_hook(payload('git push --force', cwd: dir))

      expect(status.exitstatus).to eq(0)
      output = JSON.parse(stdout).fetch('hookSpecificOutput')
      expect(output['permissionDecision']).to eq('deny')
    end
  end

  it 'releases a deny when the #rails-guard:allow bypass is present' do
    stdout, _, status = run_hook(payload('bin/rails db:drop  #rails-guard:allow'))
    expect(status.exitstatus).to eq(0)
    expect(stdout).to be_empty
  end

  it 'stays silent (exit 0, no stdout) for safe commands' do
    stdout, _, status = run_hook(payload('bundle exec rspec spec/models'))
    expect(status.exitstatus).to eq(0)
    expect(stdout).to be_empty
  end

  it 'stays silent on invalid JSON stdin' do
    stdout, _, status = run_hook('not json at all {')
    expect(status.exitstatus).to eq(0)
    expect(stdout).to be_empty
  end

  it 'respects the kill-switch' do
    stdout, _, status = run_hook(payload('bin/rails db:drop'), { 'RAILS_GUARD_DISABLE' => '1' })
    expect(status.exitstatus).to eq(0)
    expect(stdout).to be_empty
  end
end
