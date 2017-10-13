#!/usr/bin/env ruby
require 'enju_accessor'
require 'json'

enju = EnjuAccessor.new("http://localhost:38401/cgi-lilfes/enju")

text = ARGF.read
annotation = enju.parse_text(text)
puts annotation.to_json
