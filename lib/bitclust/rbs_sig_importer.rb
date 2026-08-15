# frozen_string_literal: true
#
# bitclust/rbs_sig_importer.rb
#
# RBS 型シグネチャ(.rbs)を読み込み、"Class#method"/"Class.method" キー →
# セグメント行列の対応表を作って MethodEntry の rbs_sig property に書き込む
# (rbssig サブコマンドが DB 構築後に呼ぶ)。
#
# セグメント行列は行(オーバーロードごと)の配列で、行は [種別, テキスト] の
# 組の配列。種別 "t" は素のテキスト、"c" はクラス/モジュール名(描画側=
# RbsSignatures が DB に存在するものだけリンク化する)。型名の位置は RBS
# パーサの location で厳密に取り、行のテキストを連結すると元のシグネチャ
# 文字列に戻る。rbs gem が必要なのは書き込み側のこのファイルだけで、描画側は
# property を読むだけで動く。

require 'rbs'
require 'json'
require 'pathname'

module BitClust

  class RbsSigImporter

    # core_root: ruby/rbs チェックアウトの core/(組み込みクラスの型)
    # repository_root: 同 stdlib/(core_root を与えると rbs が stringio を
    #                  暗黙に要求するので、core_root とセットで渡す)
    # sig_dirs: 素の .rbs ディレクトリ(テスト・追加分)
    def initialize(core_root: nil, repository_root: nil, sig_dirs: [])
      @core_root = core_root
      @repository_root = repository_root
      @sig_dirs = sig_dirs
      @signatures = nil
    end

    # "Class#method"/"Class.method" → セグメント行列
    def signatures
      @signatures ||= build_signatures
    end

    # bitclust の typechar('i'/'s'/'m')と名前の並び(別名)で対応表を引く。
    # モジュール関数(m)は def self?. 由来の # キーを先に、new は
    # Class.new → Class#initialize の順で引く。見つからなければ nil
    def lookup(class_name, typechar, names)
      names.each do |name|
        case typechar
        when 'i'
          sig = signatures["#{class_name}##{name}"]
        when 's'
          sig = signatures["#{class_name}.#{name}"]
          sig ||= signatures["#{class_name}#initialize"] if name == 'new'
        when 'm'
          sig = signatures["#{class_name}##{name}"] || signatures["#{class_name}.#{name}"]
        else
          return nil
        end
        return sig if sig
      end
      nil
    end

    # DB の全メソッドエントリに対応表を引き、ヒットしたものへ rbs_sig
    # property(JSON 1 行)を書き込む。書き方は MethodSinceCalculator#apply と
    # 同じ(変更があったエントリだけ save)
    def apply(db)
      stats = { entries_updated: 0, sigs_matched: 0, methods_missed: 0 } #: stats
      db.classes.each do |c|
        c.entries.each do |m|
          next if m.kind == :undefined
          next unless %w[i s m].include?(m.typechar)
          lines = lookup(c.name, m.typechar, m.names)
          unless lines
            stats[:methods_missed] += 1
            next
          end
          stats[:sigs_matched] += 1
          json = JSON.generate(lines)
          next if m.rbs_sig == json
          m.rbs_sig = json
          m.save
          stats[:entries_updated] += 1
        end
      end
      stats
    end

    private

    def build_signatures
      env = load_environment
      sigs = {} #: signatures
      aliases = [] #: Array[[String, untyped]]
      env.class_decls.each do |type_name, entry|
        class_name = type_name.to_s.delete_prefix('::')
        each_decl(entry) do |decl|
          decl.members.each do |member|
            case member
            when RBS::AST::Members::MethodDefinition
              lines = member.overloads.map {|o| method_type_segments(o.method_type.to_s) }
              method_keys(class_name, member.name, member.kind).each do |key|
                sigs[key] ||= lines
              end
            when RBS::AST::Members::AttrReader
              sigs[attr_key(class_name, member, member.name)] ||= [type_segments(member.type.to_s)]
            when RBS::AST::Members::AttrWriter
              sigs[attr_key(class_name, member, "#{member.name}=")] ||= [type_segments(member.type.to_s)]
            when RBS::AST::Members::AttrAccessor
              line = [type_segments(member.type.to_s)]
              sigs[attr_key(class_name, member, member.name)] ||= line
              sigs[attr_key(class_name, member, "#{member.name}=")] ||= line
            when RBS::AST::Members::Alias
              aliases << [class_name, member]
            end
          end
        end
      end
      resolve_aliases(sigs, aliases)
      sigs
    end

    def load_environment
      repository = RBS::Repository.new(no_stdlib: true)
      if (repository_root = @repository_root)
        repository.add(Pathname(repository_root))
      end
      core_root = @core_root
      loader = RBS::EnvironmentLoader.new(
        core_root: core_root && Pathname(core_root),
        repository: repository)
      @sig_dirs.each {|dir| loader.add(path: Pathname(dir)) }
      env = RBS::Environment.new
      loader.load(env: env)
      env
    end

    # rbs 3.x は MultiEntry#decls、rbs 4.x は entry.each_decl
    def each_decl(entry, &block)
      if entry.respond_to?(:each_decl)
        entry.each_decl(&block)
      else
        entry.decls.each {|d| block.call(d.decl) }
      end
    end

    # def self?.(kind :singleton_instance)は Class.name と Class#name の
    # 両方を定義する(bitclust のモジュール関数に対応)ので両キーに登録する
    def method_keys(class_name, name, kind)
      case kind
      when :singleton
        ["#{class_name}.#{name}"]
      when :singleton_instance
        ["#{class_name}.#{name}", "#{class_name}##{name}"]
      else
        ["#{class_name}##{name}"]
      end
    end

    def attr_key(class_name, member, name)
      member.kind == :singleton ? "#{class_name}.#{name}" : "#{class_name}##{name}"
    end

    # alias メンバーは元メソッドのシグネチャを共有する。alias が alias を
    # 指すこともあるので、解決が進まなくなるまで繰り返す
    def resolve_aliases(sigs, aliases)
      until aliases.empty?
        resolved, aliases = aliases.partition {|class_name, member|
          sigs.key?(alias_key(class_name, member, member.old_name))
        }
        break if resolved.empty?
        resolved.each do |class_name, member|
          sigs[alias_key(class_name, member, member.new_name)] ||=
            sigs[alias_key(class_name, member, member.old_name)]
        end
      end
    end

    def alias_key(class_name, member, name)
      member.kind == :singleton ? "#{class_name}.#{name}" : "#{class_name}##{name}"
    end

    # メソッド型シグネチャ 1 行をセグメント列にする
    def method_type_segments(sig)
      method_type = RBS::Parser.parse_method_type(sig, require_eof: true)
      locs = [] #: Array[[String, Integer]]
      collect_function_type_names(method_type.type, locs)
      collect_function_type_names(method_type.block.type, locs) if method_type.block
      build_segments(sig, locs)
    end

    # attr 用: 型だけの文字列をセグメント列にする
    def type_segments(sig)
      type = RBS::Parser.parse_type(sig, require_eof: true)
      locs = [] #: Array[[String, Integer]]
      collect_type_names(type, locs)
      build_segments(sig, locs)
    end

    def collect_function_type_names(fun, locs)
      fun.each_param {|param| collect_type_names(param.type, locs) }
      collect_type_names(fun.return_type, locs)
    end

    # クラス/モジュール参照(ClassInstance)の名前とその開始位置を集める。
    # location の :name 子は "::String" のように名前空間プレフィクスを含む
    # ので、end_pos から正規化名の長さを引いて名前本体の開始位置にする
    # (:: はテキストセグメント側に残る)
    def collect_type_names(type, locs)
      case type
      when RBS::Types::ClassInstance
        name = type.name.to_s.delete_prefix('::')
        if (loc = type.location)
          name_loc = loc[:name] || loc
          locs << [name, name_loc.end_pos - name.length]
        end
        type.args.each {|t| collect_type_names(t, locs) }
      when RBS::Types::Union, RBS::Types::Intersection, RBS::Types::Tuple
        type.types.each {|t| collect_type_names(t, locs) }
      when RBS::Types::Optional
        collect_type_names(type.type, locs)
      when RBS::Types::Record
        type.all_fields.each_value {|t, _required| collect_type_names(t, locs) }
      when RBS::Types::Alias
        # エイリアス型(string, hash 等)自体はクラスではないのでテキストの
        # ままにするが、ジェネリクス引数の中のクラス名は拾う
        type.args.each {|t| collect_type_names(t, locs) }
      when RBS::Types::Proc
        collect_function_type_names(type.type, locs)
      end
    end

    def build_segments(sig, locs)
      segments = [] #: segment_line
      pos = 0
      locs.sort_by {|_name, start| start }.each do |name, start|
        # 位置が既出セグメントと重なる・実文字列と一致しない型は
        # リンク化を諦めてテキストのまま残す(取りこぼしても表示は壊れない)
        next if start < pos || sig[start, name.length] != name
        segments << ['t', sig[pos...start] || raise] if start > pos
        segments << ['c', name]
        pos = start + name.length
      end
      segments << ['t', sig[pos..] || raise] if pos < sig.length
      segments
    end

  end

end
