require 'rake/testtask'
require 'yard'

task :default => [:makegem]

task :makegem do
  system "gem build quartz_torrent.gemspec"
end

Rake::TestTask.new do |t|
  t.libs << "tests"
  t.test_files = FileList['tests/test*.rb']
  t.verbose = true
end

YARD::Rake::YardocTask.new do |rd|
end

task :devinstall do
  system "sudo gem install quartz_torrent-0.0.1.gem --ignore-dependencies --no-rdoc --no-ri"
end
