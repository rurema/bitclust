# frozen_string_literal: true
#
# bitclust/rbs_overload_matcher.rb
#
# RBS のオーバーロードを、引数パターンごとに分かれた説明チャンク
# (Array.new / Array#[] のように同名メソッドの `---` 見出し+説明の組が
# 複数あるもの)へ振り分ける。RBS の引数名は rdoc の call-seq 由来で
# rurema のシグネチャの引数名とよく一致するため、
# 「ブロック有無 → 引数名の一致 → アリティ範囲の重なり」のスコアで
# 最も近いチャンクを選ぶ。1:1 対応は原理的に保証されない
# (RBS の () と (int size, ?Elem val) が rurema では同一チャンク等)ので、
# 多対 1 の割り当てとし、確実な対応が取れないオーバーロードは先頭チャンクに
# 寄せる(どのチャンクにも重複しては出さない)。
#
# オーバーロードのメタ情報(params/arity/block)は RbsSigImporter が
# rbs_sig property の JSON に書き込んだものをそのまま(文字列キーの Hash で)
# 受け取る。チャンク側は正規化済みシグネチャ行("--- " 始まり)を
# MethodSignature.parse で解析する。

require 'bitclust/methodsignature'
require 'bitclust/exception'

module BitClust

  module RbsOverloadMatcher

    module_function

    # overloads: rbs_sig JSON の overloads 配列(文字列キー Hash の配列)
    # chunks: チャンクごとの正規化済みシグネチャ行("--- " 始まり)の配列
    # 返り値: チャンクごとのオーバーロード添字の配列(chunks と同じ長さ)
    def assign(overloads, chunks)
      result = Array.new(chunks.size) { [] } #: Array[Array[Integer]]
      return result if chunks.empty?
      if chunks.size == 1
        result[0] = (0...overloads.size).to_a
        return result
      end
      features = chunks.map {|lines| chunk_features(lines) }
      overloads.each_index do |i|
        ov = overload_features(overloads[i])
        result[ov ? best_chunk(ov, features) : 0] << i
      end
      result
    end

    # チャンクのシグネチャ行群から照合用の特徴を合算する。
    # 1 行も解析できなければ nil(振り分け先にしない)
    def chunk_features(sig_lines)
      names = [] #: Array[String]
      min = nil #: Integer?
      max = 0 #: Integer?
      block = false
      parsed = false
      sig_lines.each do |line|
        begin
          sig = MethodSignature.parse(line)
        rescue ParseError
          next
        end
        parsed = true
        block ||= !sig.block.nil?
        pmin, pmax, pnames, pblock = params_features(sig.params)
        block ||= pblock
        names.concat(pnames)
        min = pmin if min.nil? || pmin < min
        max = (max && pmax) ? [max, pmax].max : nil
      end
      return nil unless parsed
      { names: names, min: min || 0, max: max, block: block }
    end

    # rbs_sig JSON のオーバーロード 1 個からスコア用の特徴を取り出す。
    # メタ情報が無いもの(#322 以前の旧形式・attr・(?) 型)は nil
    def overload_features(overload)
      arity = overload['arity']
      params = overload['params']
      block = overload['block']
      return nil unless arity || params || block
      { names: params || [],
        min: arity && arity[0],
        max: arity && arity[1],
        block: block }
    end

    # ---- 以下は実装詳細(module_function なので呼べてしまうが非公開扱い) ----

    def best_chunk(overload, features)
      best = 0
      best_score = nil #: Integer?
      features.each_with_index do |chunk, i|
        next unless chunk
        s = score(overload, chunk)
        if best_score.nil? || s > best_score
          best = i
          best_score = s
        end
      end
      best
    end

    # ブロックの一致(または矛盾)を最優先に、引数名の一致 > アリティ範囲の
    # 重なりで加点する。同点は先頭チャンク優先(best_chunk が > で更新)
    def score(overload, chunk)
      s = 0
      case overload[:block]
      when 'req'
        s += chunk[:block] ? 2 : -3
      when 'opt'
        s += 1
      else
        s += chunk[:block] ? -3 : 2
      end
      s += 2 * (overload[:names] & chunk[:names]).size
      if overload[:min] && chunk[:min]
        omax = overload[:max] || Float::INFINITY
        cmax = chunk[:max] || Float::INFINITY
        s += (overload[:min] <= cmax && chunk[:min] <= omax) ? 1 : -2
      end
      s
    end

    # シグネチャの引数リスト文字列 → [最小アリティ, 最大アリティ(nil=無制限),
    # 引数名(位置引数+キーワード名。**kwrest 名も含む), ブロック有無(&引数)]
    def params_features(params)
      return [0, 0, [], false] if params.nil? || params.strip.empty?
      required = 0
      optional = 0
      rest = false
      block = false
      names = [] #: Array[String]
      split_top_level(params).each do |token|
        token = token.strip
        next if token.empty?
        name = token[/[A-Za-z_]\w*/]
        case token
        when /\A&/
          block = true
        when /\A\*\*/
          names << name if name
        when /\A\*/, '...'
          rest = true
          names << name if name
        when /\A[A-Za-z_]\w*:/
          names << (name || raise)
        when /=/
          optional += 1
          names << name if name
        else
          required += 1
          names << name if name
        end
      end
      [required, rest ? nil : required + optional, names, block]
    end

    # 括弧((), [], {})のネストを無視して最上位の ',' で分割する
    # (デフォルト値の中の ',' で切らないため)
    def split_top_level(str)
      tokens = [+''] #: Array[String]
      depth = 0
      str.each_char do |c|
        case c
        when '(', '[', '{' then depth += 1
        when ')', ']', '}' then depth -= 1
        when ','
          if depth == 0
            tokens << +''
            next
          end
        end
        tokens.last << c
      end
      tokens
    end

  end

end
