#!/usr/bin/env ruby

require 'pathname'
$LOAD_PATH.unshift Pathname($0).realpath.dirname.dirname + 'lib'

require 'bitclust/methodsignature'

st = 0
ARGF.each do |line|
  if /\A---/ =~ line
    begin
      BitClust::MethodSignature.parse(line)
    rescue => err
      $stderr.puts "#{ARGF.filename}:#{ARGF.file.lineno}: #{line.strip.inspect}"
      st = 1
    end
  end
end
exit st
