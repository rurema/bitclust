#
# bitclust/server.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

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

end
