Gem::Specification.new do |s|
  s.name        = 'grad'
  s.version     = '0.4.3'
  s.date        = '2013-06-14'
  s.executables << 'grad'
  s.add_runtime_dependency 'apachelogregex'
  s.add_runtime_dependency 'ruby-terminfo'
  s.summary     = 'Grad - LogsReplay tool'
  s.description = 'Logs replay tool'
  s.authors     = ['Max Horlanchuk', 'David Rowe', 'Reuben Mannell']
  s.email       = 'mhorlanchuk@fairfaxmedia.com.au'
  s.files       = Dir["lib/grad.rb", "lib/grad/*.rb"]
  s.homepage    = 'https://bitbucket.org/fairfax/oh-grad'
end
