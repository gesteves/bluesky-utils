namespace :sync do
  desc "Sync preferences"
  task :preferences do
    require_relative '../../preferences'
  end

  desc "Sync blocks"
  task :blocks do
    require_relative '../../blocks'
  end

  desc "Sync blocklists"
  task :blocklists do
    require_relative '../../blocklists'
  end

  desc "Run all sync tasks"
  task :all do
    Rake::Task["sync:preferences"].invoke
    Rake::Task["sync:blocks"].invoke
    Rake::Task["sync:blocklists"].invoke
  end
end
