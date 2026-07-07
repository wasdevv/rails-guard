RSpec.describe RailsGuard::Rules do
  def match(command, cwd = RAILS_APP)
    described_class.match(command, cwd)
  end

  describe "destructive db tasks ask for confirmation" do
    [
      "bin/rails db:drop",
      "bundle exec rake db:reset",
      "rails db:migrate:reset",
      "bin/rails db:schema:load",
      "bin/rails db:setup",
      "rails db:seed:replant",
      "rake db:fixtures:load",
      "docker compose run web rails db:drop",
      "git pull && bin/rails db:reset"
    ].each do |command|
      it command do
        expect(match(command)).to include("database")
      end
    end
  end

  describe "file deletion asks for confirmation" do
    it "bin/rails destroy model User" do
      expect(match("bin/rails destroy model User")).to include("deletes generated files")
    end

    it "rails d scaffold Post" do
      expect(match("rails d scaffold Post")).to include("deletes generated files")
    end
  end

  describe "data wipes via rails runner ask for confirmation" do
    [
      "bin/rails runner 'User.delete_all'",
      %(rails runner "Account.destroy_all"),
      "bin/rails r 'ActiveRecord::Base.connection.truncate(:users)'"
    ].each do |command|
      it command do
        expect(match(command)).to include("wipes records")
      end
    end
  end

  describe "safe commands stay silent" do
    [
      "bin/rails db:migrate",
      "bin/rails db:rollback",
      "bin/rails db:migrate:status",
      "bundle exec rspec",
      "ls -la",
      "git status",
      "bin/rails dbconsole",
      "bin/rails runner 'puts User.count'",
      "bin/rails runner script/report.rb",
      "bin/rails generate model User",
      "psql -c 'DROP TABLE users'"
    ].each do |command|
      it command do
        expect(match(command)).to be_nil
      end
    end
  end

  describe "the test database is disposable" do
    [
      "RAILS_ENV=test bin/rails db:reset",
      "bin/rails db:test:prepare",
      "RAILS_ENV=test bundle exec rake db:drop db:create",
      "bin/rails runner -e test 'User.delete_all'"
    ].each do |command|
      it command do
        expect(match(command)).to be_nil
      end
    end
  end

  describe ".rails-guard.yml" do
    it "allow: silences a built-in rule" do
      app = make_rails_app("allow:\n  - 'db:reset'\n")
      expect(match("bin/rails db:reset", app)).to be_nil
      expect(match("bin/rails db:drop", app)).to include("database")
    ensure
      FileUtils.remove_entry(app)
    end

    it "ask: adds a custom rule with its own reason" do
      app = make_rails_app("ask:\n  - pattern: 'kamal app remove'\n    reason: 'removes the production containers'\n")
      expect(match("kamal app remove", app)).to include("removes the production containers")
    ensure
      FileUtils.remove_entry(app)
    end

    it "invalid YAML is ignored (fail-safe)" do
      app = make_rails_app("allow: [unclosed\n  bad yaml: :::")
      expect(match("bin/rails db:drop", app)).to include("database")
    ensure
      FileUtils.remove_entry(app)
    end
  end
end
