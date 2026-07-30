# frozen_string_literal: true

RSpec.describe RailsGuard::Rules do
  def match(command, cwd = RAILS_APP)
    described_class.match(command, cwd)
  end

  def decision(command, cwd = RAILS_APP)
    described_class.decision(command, cwd)
  end

  # ---------------------------------------------------------------------------
  # Legacy helper — still used by older tests that only care about the reason
  # string. Wraps the new two-value return so existing assertions keep working.
  # ---------------------------------------------------------------------------

  describe 'DENY — irrecoverable commands (Rails project)' do
    describe 'db:drop, db:reset and db:schema:load are denied' do
      [
        'bin/rails db:drop',
        'bundle exec rake db:drop',
        'docker compose run web rails db:drop',
        'bin/rails db:reset',
        'bundle exec rake db:reset',
        'git pull && bin/rails db:reset',
        'bin/rails db:schema:load',
        'rake db:schema:load'
      ].each do |command|
        it command do
          result = decision(command)
          expect(result[:decision]).to eq('deny')
          expect(result[:reason]).to include('database')
          # deny message must contain the bypass hint
          expect(result[:reason]).to include('#rails-guard:allow')
        end
      end
    end

    describe 'rm -rf of a swarm worktree is denied' do
      [
        'rm -rf ~/.swarm/worktrees/my-project-1/my-task',
        'rm -rf /home/user/.swarm/worktrees/proj-2/slug'
      ].each do |command|
        it command do
          result = decision(command)
          expect(result[:decision]).to eq('deny')
          expect(result[:reason]).to include('#rails-guard:allow')
        end
      end
    end

    it 'rm -rf of non-worktree path does not trigger worktree rule' do
      expect(decision('rm -rf /tmp/somedir')).to be_nil
    end

    it 'git worktree remove --force is denied' do
      result = decision('git worktree remove --force my-worktree')
      expect(result[:decision]).to eq('deny')
      expect(result[:reason]).to include('#rails-guard:allow')
    end

    it 'git worktree remove without --force is silent' do
      expect(decision('git worktree remove my-worktree')).to be_nil
    end

    describe 'git push --force is denied' do
      [
        'git push --force',
        'git push -f',
        'git push origin main --force',
        'git push -f origin main'
      ].each do |command|
        it command do
          result = decision(command)
          expect(result[:decision]).to eq('deny')
          expect(result[:reason]).to include('#rails-guard:allow')
        end
      end
    end

    it 'git push --force-with-lease is NOT denied (safe by design)' do
      expect(decision('git push --force-with-lease')).to be_nil
    end

    describe 'git reset --hard targeting main or master is denied' do
      [
        'git reset --hard main',
        'git reset --hard master',
        'git reset --hard origin/main',
        'git reset --hard origin/master'
      ].each do |command|
        it command do
          result = decision(command)
          expect(result[:decision]).to eq('deny')
          expect(result[:reason]).to include('#rails-guard:allow')
        end
      end
    end

    it 'git reset --hard on a feature branch is NOT denied' do
      expect(decision('git reset --hard HEAD~1')).to be_nil
      expect(decision('git reset --hard abc1234')).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # ASK — confirmation required, not outright blocked
  # ---------------------------------------------------------------------------

  describe 'ASK — destructive db tasks (Rails project)' do
    [
      'rails db:migrate:reset',
      'bin/rails db:setup',
      'rails db:seed:replant',
      'rake db:fixtures:load',
      'git pull && bin/rails db:setup'
    ].each do |command|
      it command do
        result = decision(command)
        expect(result[:decision]).to eq('ask')
        expect(result[:reason]).to include('database')
      end
    end
  end

  describe 'ASK — file deletion (Rails project)' do
    it 'bin/rails destroy model User' do
      result = decision('bin/rails destroy model User')
      expect(result[:decision]).to eq('ask')
      expect(result[:reason]).to include('deletes generated files')
    end

    it 'rails d scaffold Post' do
      result = decision('rails d scaffold Post')
      expect(result[:decision]).to eq('ask')
      expect(result[:reason]).to include('deletes generated files')
    end
  end

  describe 'ASK — data wipes via rails runner (Rails project)' do
    [
      "bin/rails runner 'User.delete_all'",
      %(rails runner "Account.destroy_all"),
      "bin/rails r 'ActiveRecord::Base.connection.truncate(:users)'"
    ].each do |command|
      it command do
        result = decision(command)
        expect(result[:decision]).to eq('ask')
        expect(result[:reason]).to include('wipes records')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Non-Rails rules fire outside a Rails project; Rails rules do not
  # ---------------------------------------------------------------------------

  describe 'gate: requires_rails rules are silent outside a Rails project' do
    let(:non_rails_dir) { Dir.mktmpdir('non-rails') }
    after { FileUtils.remove_entry(non_rails_dir) }

    it 'db:drop does not trigger outside a Rails project' do
      expect(decision('bin/rails db:drop', non_rails_dir)).to be_nil
    end

    it 'rails destroy does not trigger outside a Rails project' do
      expect(decision('rails destroy model User', non_rails_dir)).to be_nil
    end

    it 'rails runner wipe does not trigger outside a Rails project' do
      expect(decision("rails runner 'User.delete_all'", non_rails_dir)).to be_nil
    end
  end

  describe 'gate: non-Rails rules fire outside a Rails project' do
    let(:non_rails_dir) { Dir.mktmpdir('non-rails') }
    after { FileUtils.remove_entry(non_rails_dir) }

    it 'git push --force fires outside a Rails project' do
      result = decision('git push --force', non_rails_dir)
      expect(result[:decision]).to eq('deny')
    end

    it 'git worktree remove --force fires outside a Rails project' do
      result = decision('git worktree remove --force wt', non_rails_dir)
      expect(result[:decision]).to eq('deny')
    end

    it 'rm -rf worktree fires outside a Rails project' do
      result = decision('rm -rf ~/.swarm/worktrees/x/y', non_rails_dir)
      expect(result[:decision]).to eq('deny')
    end

    it 'git reset --hard main fires outside a Rails project' do
      result = decision('git reset --hard main', non_rails_dir)
      expect(result[:decision]).to eq('deny')
    end
  end

  # ---------------------------------------------------------------------------
  # Bypass inline — #rails-guard:allow
  # ---------------------------------------------------------------------------

  describe '#rails-guard:allow inline bypass' do
    it 'releases a deny (db:drop) when the bypass comment is present' do
      expect(decision('bin/rails db:drop  #rails-guard:allow')).to be_nil
    end

    it 'releases a deny (git push --force) when the bypass comment is present' do
      expect(decision('git push --force  #rails-guard:allow')).to be_nil
    end

    it 'releases an ask (db:migrate:reset) when the bypass comment is present' do
      expect(decision('bin/rails db:migrate:reset  #rails-guard:allow')).to be_nil
    end

    it 'does NOT trigger on a command that merely mentions the bypass but has no rule match' do
      # Safe command + bypass → still nil (no double-nil confusion)
      expect(decision('git status  #rails-guard:allow')).to be_nil
    end

    it 'does NOT falsely pass the bypass to an unrelated command' do
      # Command without #rails-guard:allow must still be caught
      expect(decision('bin/rails db:drop')).not_to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Test environment exemption
  # ---------------------------------------------------------------------------

  describe 'the test database is disposable' do
    [
      'RAILS_ENV=test bin/rails db:reset',
      'RAILS_ENV=test bin/rails db:drop',
      'RAILS_ENV=test bin/rails db:schema:load',
      'bin/rails db:test:prepare',
      'RAILS_ENV=test bundle exec rake db:drop db:create',
      "bin/rails runner -e test 'User.delete_all'"
    ].each do |command|
      it command do
        expect(decision(command)).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Safe commands stay silent
  # ---------------------------------------------------------------------------

  describe 'safe commands stay silent' do
    [
      'bin/rails db:migrate',
      'bin/rails db:rollback',
      'bin/rails db:migrate:status',
      'bundle exec rspec',
      'ls -la',
      'git status',
      'bin/rails dbconsole',
      "bin/rails runner 'puts User.count'",
      'bin/rails runner script/report.rb',
      'bin/rails generate model User',
      "psql -c 'DROP TABLE users'",
      'git push --force-with-lease',
      'git reset --hard HEAD~1',
      'git reset --hard abc1234',
      'rm -rf /tmp/somedir',
      'git worktree remove my-worktree'
    ].each do |command|
      it command do
        expect(decision(command)).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .rails-guard.yml
  # ---------------------------------------------------------------------------

  describe '.rails-guard.yml' do
    it 'allow: silences a built-in rule' do
      app = make_rails_app("allow:\n  - 'db:reset'\n")
      expect(decision('bin/rails db:reset', app)).to be_nil
      expect(decision('bin/rails db:drop', app)).not_to be_nil
    ensure
      FileUtils.remove_entry(app)
    end

    it 'ask: adds a custom rule with its own reason' do
      app = make_rails_app("ask:\n  - pattern: 'kamal app remove'\n    reason: 'removes the production containers'\n")
      result = decision('kamal app remove', app)
      expect(result[:decision]).to eq('ask')
      expect(result[:reason]).to include('removes the production containers')
    ensure
      FileUtils.remove_entry(app)
    end

    it 'invalid YAML is ignored (fail-safe)' do
      app = make_rails_app("allow: [unclosed\n  bad yaml: :::")
      expect(decision('bin/rails db:drop', app)).not_to be_nil
    ensure
      FileUtils.remove_entry(app)
    end
  end

  # ---------------------------------------------------------------------------
  # Legacy match() API — returns reason string (or nil); used by older callers
  # ---------------------------------------------------------------------------

  describe 'legacy match() API' do
    it 'returns the reason string for a matched rule' do
      expect(match('bin/rails db:drop')).to include('database')
    end

    it 'returns nil for a safe command' do
      expect(match('bin/rails db:migrate')).to be_nil
    end

    it 'returns nil for inline bypass' do
      expect(match('bin/rails db:drop  #rails-guard:allow')).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Deny message quality — the message is the product
  # ---------------------------------------------------------------------------

  describe 'deny message content' do
    it 'db:drop message explains irrecoverability, gives alternative, and includes bypass hint' do
      result = decision('bin/rails db:drop')
      expect(result[:reason]).to include('irrecoverable')
      expect(result[:reason]).to include('#rails-guard:allow')
    end

    it 'db:schema:load message explains irrecoverability and includes bypass hint' do
      result = decision('bin/rails db:schema:load')
      expect(result[:reason]).to include('irrecoverable')
      expect(result[:reason]).to include('#rails-guard:allow')
    end

    it 'git push --force message mentions alternative and bypass hint' do
      result = decision('git push --force')
      expect(result[:reason]).to include('--force-with-lease')
      expect(result[:reason]).to include('#rails-guard:allow')
    end

    it 'git reset --hard main message mentions irreversibility and bypass hint' do
      result = decision('git reset --hard main')
      expect(result[:reason]).to include('#rails-guard:allow')
    end

    # The reason template interpolates the matched fragment, which already
    # carries the "db:" prefix — a template of "db:%s" would render "db:db:drop".
    it 'names the rake task exactly once' do
      expect(decision('bin/rails db:drop')[:reason]).to start_with('db:drop drops')
      expect(decision('bin/rails db:reset')[:reason]).to start_with('db:reset drops')
      expect(decision('bin/rails db:setup')[:reason]).to start_with('db:setup rewrites')
    end
  end
end
