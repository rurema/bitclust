# -*- ruby -*-

baseurl = nil
basepath = ''
themedir = nil
%w[theme bitclust/theme ../bitclust/theme].each do |theme|
  dir = File.expand_path(theme, File.dirname(__FILE__))
  if File.directory?(dir)
    themedir = dir
  end
end

$LOAD_PATH.unshift File.expand_path('lib', File.dirname(__FILE__))
$LOAD_PATH.unshift File.expand_path('bitclust/lib', File.dirname(__FILE__))
require 'bitclust/app'

dbpath = Dir.glob("db-*")
if dbpath.empty?
  raise 'database not found' unless File.directory? 'db'
  app = BitClust::App.new(
    :dbpath => 'db',
    :viewpath => "/view/",
    :rack => true
    )
  app.interfaces.each do |viewpath, interface|
    map viewpath do
      run interface
    end
  end
else
  app = BitClust::App.new(
    :dbpath => dbpath,
    :rack => true
    )
  app.interfaces.each do |version, interface|
    map "#{basepath}/#{version}/" do
      run interface
    end
  end
end

map "#{basepath}/" do
  run app
end

map File.join(basepath, 'theme/') do
  run Rack::File.new(themedir)
end
