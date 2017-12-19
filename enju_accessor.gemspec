Gem::Specification.new do |s|
  s.name        = 'enju_accessor'
  s.version     = '1.0'
  s.summary     = 'A wrapper for Enju CGI service to convert the output to the PubAnnotation JSON format.'
  s.date        = Time.now.utc.strftime("%Y-%m-%d")
  s.description = 'A wrapper for Enju CGI service to convert the output to the PubAnnotation JSON format.'
  s.authors     = ["Jin-Dong Kim"]
  s.email       = 'jindong.kim@gmail.com'
  s.files       = ["lib/enju_accessor.rb", "lib/enju_accessor/enju_accessor.rb"]
  s.executables << 'enju_parse_text'
  s.executables << 'enju_tag_text'
  s.add_runtime_dependency 'text_sentencer', '~> 1.0.2'
  s.homepage    = 'https://github.com/jdkim/enju_accessor'
  s.license     = 'MIT'
end