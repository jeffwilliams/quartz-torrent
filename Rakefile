require 'rake/testtask'
require 'yard'

$gemfile_name = nil

task :default => [:makegem]

task :makegem do
  output = `gem build quartz_torrent.gemspec`
  output.each_line do |line|
    $gemfile_name = $1 if line =~ /File: (.*)$/
    print line
  end
end

Rake::TestTask.new do |t|
  t.libs << "tests"
  t.test_files = FileList['tests/test*.rb']
  t.verbose = true
end

YARD::Rake::YardocTask.new do |rd|
end

task :devinstall => [:makegem] do
  system "sudo gem install #{$gemfile_name} --ignore-dependencies --no-rdoc --no-ri"
end
