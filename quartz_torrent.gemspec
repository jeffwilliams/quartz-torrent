Gem::Specification.new do |s|
  git_tag = `git describe --tags --long --match 'v*'`.chomp!
  version = nil
  puts "Most recent git version tag: '#{git_tag}'"

  if git_tag =~ /^v(\d+)\.(\d+)\.(\d+)-(\d+)/
    commits_since = $4.to_i
    maj, min, bug = $1.to_i, $2.to_i, $3.to_i
    if commits_since > 0
      version = "#{maj}.#{min}.#{bug+1}.pre"
    else
      version = "#{maj}.#{min}.#{bug}"
    end
  else
    puts "Warning: Couldn't get the latest git tag using git describe. Defaulting to 0.0.1"
    version = "0.0.1"
  end

  s.name        = 'quartz_torrent'
  s.version     = version
  s.date        = Time.new
  s.license     = 'MIT'
  s.summary     = "A bittorrent library"
  s.description = "A pure ruby bittorrent library"
  s.authors     = ["Jeff Williams"]
  s.files       = Dir['lib/*.rb'] + Dir['lib/quartz_torrent/*.rb'] + ['README.md', 'LICENSE', '.yardopts']
  s.homepage    =
    'https://github.com/jeffwilliams/quartz-torrent'

  s.executables = [
    "quartztorrent_download",
    "quartztorrent_download_curses",
    "quartztorrent_magnet_from_torrent",
    "quartztorrent_show_info",
  ]

  s.required_ruby_version = '~> 1.9'

  s.add_runtime_dependency "bencode", '~> 0.8'
  s.add_runtime_dependency "pqueue", '~> 2.0'
  s.add_runtime_dependency "base32", '~> 0.2'
  s.add_runtime_dependency "log4r", '~> 1.1'

  s.add_development_dependency "minitest"
  s.add_development_dependency "yard"
  s.add_development_dependency "redcarpet"
end
