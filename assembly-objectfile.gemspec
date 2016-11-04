$LOAD_PATH.push File.expand_path("../lib", __FILE__)
require 'assembly-objectfile/version'

Gem::Specification.new do |s|
  s.name        = 'assembly-objectfile'
  s.version     = Assembly::ObjectFile::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Peter Mangiafico", "Renzo Sanchez-Silva","Monty Hindman","Tony Calavano"]
  s.email       = ["pmangiafico@stanford.edu"]
  s.homepage    = 'https://github.com/sul-dlss/assembly-objectfile'
  s.summary     = %q{Ruby immplementation of file services needed to prepare objects to be accessioned in SULAIR digital library}
  s.description = %q{Get exif data, file sizes and more.}
  s.license     = 'ALv2'

  s.rubyforge_project = 'assembly-objectfile'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- spec/*`.split("\n")
  s.bindir        = 'exe'
  s.executables   = s.files.grep(%r{^exe/}) { |f| File.basename(f) }
  s.require_paths = ['lib']

  s.add_dependency 'mini_exiftool'
  s.add_dependency 'mime-types'
  s.add_dependency 'nokogiri'

  s.add_development_dependency 'rake'
  s.add_development_dependency 'json'
  s.add_development_dependency "rspec", "~> 3.0"
  s.add_development_dependency "yard"
  
end
