# frozen_string_literal: true
#
# bitclust/methodentry.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/entry'
require 'bitclust/exception'

module BitClust

  # Entry for methods(instance methods/singleton methods/module_functions),
  # constants and special variables(like $!).
  class MethodEntry < Entry

    def MethodEntry.type_id
      :method
    end

    def initialize(db, id)
      super db
      @id = id
      init_properties
    end

    attr_reader :id

    def ==(other)
      return false if self.class != other.class
      @id == other.id
    end

    alias eql? ==

    def hash
      @id.hash
    end

    def <=>(other)
      sort_key() <=> other.sort_key
    end

    KIND_NUM = {:defined => 0, :redefined => 1, :added => 2,
                :undefined => 3, :nomethod => 4}

    def sort_key
      [label(), KIND_NUM[kind()]]
    end

    def name
      methodid2mname(@id)
    end

    # typename = :singleton_method
    #          | :instance_method
    #          | :module_function
    #          | :constant
    #          | :special_variable
    def typename
      methodid2typename(@id)
    end

    alias type typename

    def typemark
      methodid2typemark(@id)
    end

    def typechar
      methodid2typechar(@id)
    end

    # bitclust#250: 表示専用の typemark。DB のバージョンが 4.0 以降なら
    # module function の "." を "?." にする(それ以外の typemark は不変)。
    # typemark 自体(識別子として使う方)は変えない -- URL・spec 文字列・
    # refsdatabase のアンカーキー等はすべて typemark() 経由のまま
    def display_typemark
      NameUtils.display_typemark(typemark(), @db.propget('version'))
    end

    def type_label
      case typemark()
      when '.'  then 'singleton method'
      when '#'  then 'instance method'
      when '.#' then 'module function'
      when '::' then 'constant'
      when '$'  then 'variable'
      else raise "invalid typemark: #{typemark().inspect}"
      end
    end

    def library
      @library ||= @db.fetch_library_id(methodid2libid(@id))
    end

    attr_writer :library

    def klass
      @klass ||= @db.fetch_class_id(methodid2classid(@id))
    end

    attr_writer :klass

    persistent_properties {
      property :names,           '[String]'
      property :visibility,      'Symbol'   ## :public | :private | :protected
      property :kind,            'Symbol'   ## :defined | :added | :redefined | :undefined | :nomethod
      property :source,          'String'
      property :source_location, 'Location'
      # 名前別の since/until（bitclust#132）。トークンは
      # "#{エンコード名}=#{バージョン}" の配列（[String] 型を再利用）で、
      # 生名の ',' '=' は encodename_url でエスケープ済みなので最後の '='
      # がバージョンとの区切りになる（バージョン文字列には '=' も ',' も
      # 現れない前提。fill_since/fill_until で検査する）
      property :since_by_name,   '[String]'
      property :until_by_name,   '[String]'
    }

    def inspect
      c, t, _m, _lib = methodid2specparts(@id)
      "\#<method #{c}#{t}#{names().join(',')}>"
    end

    def spec
      c, t, m, lib = methodid2specparts(@id)
      MethodSpec.new(c, t, m, lib)
    end

    def spec_string
      methodid2specstring(@id)
    end

    def label
      c, t, m, _lib = methodid2specparts(@id)
      "#{t == '$' ? '' : c}#{t}#{m}"
    end

    # bitclust#250: label の表示専用版(module function は 4.0 以降 "?." で
    # 表示)。label 自身は refsdatabase.rb の [[a:...]] アンカーキーや
    # `bitclust methods --diff` の突き合わせが literal ".#" 前提で使うので
    # 変えない -- テンプレート側の実際の表示箇所だけがこちらを呼ぶ
    def display_label
      c, t, m, _lib = methodid2specparts(@id)
      "#{t == '$' ? '' : c}#{display_typemark}#{m}"
    end

    def short_label
      _c, t, m, _lib = methodid2specparts(@id)
      "#{t == '#' ? '' : t}#{m}"
    end

    # bitclust#250: short_label の表示専用版。short_label 自身の唯一の
    # 呼び出し元(htmlutils.rb の link_to_method)は display_short_label に
    # 切り替え済みだが、short_label 自体は同じ理由(識別子的な使い方をする
    # 将来のコードのため)で変えない
    def display_short_label
      _c, t, m, _lib = methodid2specparts(@id)
      "#{t == '#' ? '' : display_typemark}#{m}"
    end

    def index_id
      "#{methodid2typechar(@id)}_#{encodename_fs(name).gsub(/=/, '--')}".upcase
    end

    def labels
      c, t, _m, _lib = methodid2specparts(@id)
      names().map {|name| "#{c}#{t}#{name}" }
    end

    # Every name of this entry, formatted the same way as #label (i.e.
    # without the redundant class prefix on special variables such as $!,
    # unlike #labels). Used where all aliases of a method need to be listed
    # together, e.g. the <title> of its page.
    def title_labels
      c, t, _m, _lib = methodid2specparts(@id)
      names().map {|name| "#{t == '$' ? '' : c}#{t}#{name}" }
    end

    # bitclust#250: title_labels の表示専用版(<title> タグ・見出しで使う)
    def display_title_labels
      c, t, _m, _lib = methodid2specparts(@id)
      names().map {|name| "#{t == '$' ? '' : c}#{display_typemark}#{name}" }
    end

    def name?(name)
      names().include?(name)
    end

    # 名前別 since/until（bitclust#132）。名前ごとに別バージョンで
    # 追加/削除されうる別名（例: alias）を区別して記録する

    def since_of(name)
      since_map[name]
    end

    def until_of(name)
      until_map[name]
    end

    def since_map
      decode_version_tokens(since_by_name)
    end

    def until_map
      decode_version_tokens(until_by_name)
    end

    # name の since が未設定の場合のみ version を追加する。追加したら true、
    # 既に値があって何もしなければ false を返す
    def fill_since(name, version)
      fill_version_token(:since_by_name, :since_of, name, version)
    end

    # fill_since の until 版
    def fill_until(name, version)
      fill_version_token(:until_by_name, :until_of, name, version)
    end

    private

    def decode_version_tokens(tokens)
      h = {} #: Hash[String, String]
      tokens.each do |token|
        i = token.rindex('=') or raise "must not happen: malformed version token #{token.inspect}"
        raw_name = decodename_url(token[0...i] || raise)
        h[raw_name] = token[(i + 1)..] || raise
      end
      h
    end

    def fill_version_token(prop, reader, name, version)
      if version.include?('=') || version.include?(',')
        raise ArgumentError, "version must not contain '=' or ',': #{version.inspect}"
      end
      return false if __send__(reader, name)
      token = "#{encodename_url(name)}=#{version}"
      __send__("#{prop}=", __send__(prop) + [token])
      true
    end

    public

    def name_match?(re)
      names().any? {|n| re =~ n }
    end

    def really_public?
      visibility() == :public
    end

    def public?
      visibility() != :private && visibility() != :protected
    end

    def protected?
      visibility() == :protected
    end

    def private?
      visibility() == :private
    end

    def public_singleton_method?
      singleton_method? and public?
    end

    def private_singleton_method?
      singleton_method? and private?
    end

    def public_instance_method?
      instance_method? and public?
    end

    def private_instance_method?
      instance_method? and private?
    end

    def protected_instance_method?
      instance_method? and protected?
    end

    def singleton_method?
      t = typename()
      t == :singleton_method or t == :module_function
    end

    def instance_method?
      t = typename()
      t == :instance_method or t == :module_function
    end

    def constant?
      typename() == :constant
    end

    def special_variable?
      typename() == :special_variable
    end

    def defined?
      kind() == :defined
    end

    def added?
      kind() == :added
    end

    def redefined?
      kind() == :redefined
    end

    def undefined?
      kind() == :undefined
    end

    # 説明のためだけに記載されていて実際には定義されていないメソッド
    # （ソースの @nomethod メタデータ行で指定する）
    def nomethod?
      kind() == :nomethod
    end

    def description
      paragraphs = source.split(/\n\n+/).drop(1)
      # {: ...} 属性行や @param などのメタデータ段落は説明文として使わない
      para = paragraphs.find {|p| !p.start_with?('@', '{:') } || paragraphs.first || ''
      description_text(para)
    end
  end
end
