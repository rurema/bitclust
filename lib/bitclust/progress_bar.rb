
begin
  require 'progressbar'
rescue LoadError
  require 'bitclust/silent_progress_bar'
  ProgressBar = BitClust::SilentProgressBar
end
