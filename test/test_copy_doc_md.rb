# frozen_string_literal: true

require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'bitclust'
require 'bitclust/methoddatabase'

# copy_doc_md: manual/doc 配下の md をファイル存在で doc ページとして登録する。
# front matter の since/until でページ自体をバージョンで出し分けられることを
# 確認する（ライブラリ側と同じ意味論）。
class TestCopyDocMd < Test::Unit::TestCase
  def docs_for(version)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'manual', 'api'))
      FileUtils.mkdir_p(File.join(dir, 'manual', 'doc', 'spec'))
      File.write(File.join(dir, 'manual', 'doc', 'spec', 'gated.md'),
                 "---\nuntil: \"3.2\"\n---\n# ゲート付きページ\n\n本文。\n")
      File.write(File.join(dir, 'manual', 'doc', 'spec', 'since.md'),
                 "---\nsince: \"3.3\"\n---\n# 新機能ページ\n\n本文。\n")
      File.write(File.join(dir, 'manual', 'doc', 'spec', 'normal.md'),
                 "# 通常ページ\n\n本文。\n")

      prefix = File.join(dir, 'db')
      db = BitClust::MethodDatabase.new(prefix)
      db.init
      db.transaction do
        db.propset('version', version)
        db.propset('encoding', 'utf-8')
      end
      db.transaction do
        db.instance_variable_set(:@md_root, File.join(dir, 'manual', 'api'))
        db.__send__(:copy_doc_md)
      end
      db2 = BitClust::MethodDatabase.new(prefix)
      return db2.docs.each_with_object({}) { |d, h| h[d.id] = d.title }
    end
  end

  def test_until_gate_before_threshold
    docs = docs_for('3.0')
    assert_equal 'ゲート付きページ', docs['spec.gated']   # until: 3.2 → 3.0 は表示
    assert_nil docs['spec.since']                         # since: 3.3 → 3.0 は非表示
    assert_equal '通常ページ', docs['spec.normal']
  end

  def test_until_gate_after_threshold
    docs = docs_for('3.4')
    assert_nil docs['spec.gated']                         # until: 3.2 → 3.4 は非表示
    assert_equal '新機能ページ', docs['spec.since']       # since: 3.3 → 3.4 は表示
    assert_equal '通常ページ', docs['spec.normal']
  end
end
