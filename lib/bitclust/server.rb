#
# bitclust/server.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/methoddatabase'
require 'bitclust/functiondatabase'
require 'bitclust/libraryentry'
require 'bitclust/classentry'
require 'bitclust/methodentry'
require 'bitclust/docentry'
require 'drb'
require 'webrick/server'

module BitClust

  class Server

    def initialize(db)
      @db = db
    end

    def listen(url, foreground = false)
      WEBrick::Daemon.start unless foreground
      DRb.start_service url, @db
      DRb.thread.join
    end

  end

  class Database   # reopen
    include DRb::DRbUndumped
  end

  class Entry   # reopen
    include DRb::DRbUndumped
  end

  class SearchResult   # reopen
    include DRb::DRbUndumped
  end

end

class Object
  def _remote_object?
    false
  end
end

class DRb::DRbObject
  def _remote_object?
    true
  end
end
