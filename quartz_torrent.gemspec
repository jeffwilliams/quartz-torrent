Gem::Specification.new do |s|
  s.name        = 'quartz_torrent'
  s.version     = '0.0.1'
  s.date        = '2013-08-11'
  s.summary     = "A bittorrent library"
  s.description = "A pure ruby bittorrent library"
  s.authors     = ["Jeff Williams"]
  s.files       = Dir['lib/*.rb'] + Dir['lib/quartz_torrent/*.rb']
  s.homepage    =
    'https://github.com/jeffwilliams/quartz-torrent'

  s.add_runtime_dependency "bencode", '~> 0.8'
  s.add_runtime_dependency "pqueue", '~> 2.0'
  s.add_runtime_dependency "base32", '~> 0.2'

  s.add_development_dependency "minitest"
end
