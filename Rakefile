# Development tasks. Rake and minitest are bundled gems, so run these on a Ruby
# that has them (mise's does); the plugin itself runs on the standard library.

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/shell/**")
  t.warning = false
end

namespace :test do
  # Drives the widget in the running shell; see test/shell/shell_helper.rb.
  Rake::TestTask.new(:shell) do |t|
    t.description = "Run the widget end to end in the running shell, in test mode"
    t.libs << "lib" << "test"
    t.test_files = FileList["test/shell/**/*_test.rb"]
    t.warning = false
  end
end

task default: :test

def mast
  $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
  require "mast"
end

namespace :db do
  desc "Bring MAST_ENV's database up to date (production unless set)"
  task :migrate do
    mast
    Mast.db
    puts "#{Mast.env}: #{Mast.database_path}"
  end

  desc "Delete MAST_ENV's database and migrate a fresh one; refuses production"
  task :reset do
    mast
    abort "db:reset refuses to delete the production record" if Mast.env == "production"
    FileUtils.rm_f(Dir["#{Mast.database_path}*"])
    Mast.db
    puts "#{Mast.env}: #{Mast.database_path}"
  end
end

namespace :passages do
  def passages
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "mast/passages"
  end

  desc "Cut config/books.yml into candidate passages in tmp/candidates, to read and pick from"
  task :candidates do
    passages
    Mast::Passages.write_candidates
  end

  desc "Write the passages picked in config/passage_picks.yml to config/passages.json"
  task :build do
    passages
    Mast::Passages.build
  end
end
