# frozen_string_literal: true
#
# ユーザーごとの設定ファイル・DB・キャッシュの置き場所。
# XDG Base Directory(XDG_CONFIG_HOME / XDG_DATA_HOME / XDG_CACHE_HOME、
# 未設定なら ~/.config ~/.local/share ~/.cache)配下の bitclust/ を使い、
# 従来の ~/.bitclust は互換のため読み取りの fallback として残す。

require 'pathname'
require 'yaml'

module BitClust
  module UserDirs
    module_function

    def home
      Pathname(ENV.fetch('HOME')).expand_path
    end

    # 従来の置き場所(bitclust setup が 1.7 まで作っていた場所)
    def legacy_dir
      home + '.bitclust'
    end

    def config_home
      xdg_dir('XDG_CONFIG_HOME', '.config')
    end

    def data_home
      xdg_dir('XDG_DATA_HOME', File.join('.local', 'share'))
    end

    def cache_home
      xdg_dir('XDG_CACHE_HOME', '.cache')
    end

    # 設定ファイルの候補(優先順)
    def config_candidates
      [config_home + 'config', legacy_dir + 'config']
    end

    # 存在する設定ファイル。XDG の場所を先に見て、無ければ従来の
    # ~/.bitclust/config。どちらも無ければ nil
    def config_file
      config_candidates.find(&:exist?)
    end

    # 設定ファイルを読む。無ければ nil
    def load_config
      path = config_file
      path ? YAML.load_file(path) : nil
    end

    # 環境変数が絶対パスならそれを、無ければ HOME 直下の既定を使う
    # (XDG の仕様では相対パスの指定は無視する)
    def xdg_dir(env_key, default_subdir)
      value = ENV[env_key]
      base = (value && Pathname(value).absolute?) ? Pathname(value) : home + default_subdir
      base + 'bitclust'
    end
    private_class_method :xdg_dir
  end
end
