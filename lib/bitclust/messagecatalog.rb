#
# bitclust/messagecatalog.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

module BitClust

  module Translatable

    private

    def init_message_catalog(catalog)
      @__message_catalog = catalog
    end

    def message_catalog
      @__message_catalog
    end

    def _(key, *args)
      @__message_catalog.translate(key, *args)
    end

  end

  # FIXME: support automatic encoding-conversion
  class MessageCatalog

    ENCODING_MAP = {
      'utf-8' => 'UTF-8',
      'euc-jp' => 'EUC-JP',
      'shift_jis' => 'Shift_JIS'
    }

    # FIXME: support non ja_JP locales
    def MessageCatalog.encoding2locale(enc)
      newenc = ENCODING_MAP[enc.downcase]
      newenc ? "ja_JP.#{newenc}" : "C"
    end

    def MessageCatalog.load(prefix)
      load_with_locales(prefix, env_locales())
    end

    def MessageCatalog.load_with_locales(prefix, locales)
      path, loc = find_catalog(prefix, locales)
      path ? load_file(path, loc) : new({}, 'C')
    end

    def MessageCatalog.env_locales
      [ENV['LC_MESSAGES'], ENV['LC_ALL'], ENV['LANG'], 'C']\
          .compact.uniq.reject {|loc| loc.empty? }
    end
    private_class_method :env_locales

    def MessageCatalog.find_catalog(prefix, locales)
      locales.each do |locale|
        path = "#{prefix}/#{locale}"
        return path, locale if File.file?(path)
      end
      nil
    end
    private_class_method :find_catalog

    def MessageCatalog.load_file(path, locale)
      h = {}
      fopen(path, 'r:EUC-JP') {|f|
        f.each do |key|
          h[key.chomp] = f.gets.chomp
        end
      }
      new(h, locale)
    end
      
    def initialize(msgs, locale)
      @msgs = msgs
      @locale = locale
    end

    def inspect
      "\#<#{self.class} #{@locale}>"
    end

    def translate(key, *args)
      str = @msgs[key] || key
      sprintf(str, *args)
    end

  end

end
