# Development tasks. Rake and minitest are bundled gems, so run these on a Ruby
# that has them (mise's does); the plugin itself runs on the standard library.

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
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
  desc "Fetch and rank a new passage pool now (NO_RANK=1 for keyword picks)"
  task :refresh do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "mast/passages"
    Mast::Passages::Pool.new.refresh(force: true, rank: !ENV["NO_RANK"])
  end
end
