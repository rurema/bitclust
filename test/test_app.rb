# frozen_string_literal: true
require 'test/unit'
require 'bitclust'
require 'bitclust/app'
require 'rack'
require 'rack/mock'
require 'webrick'
require 'tmpdir'
require 'fileutils'
require 'stringio'

# bitclust#275: `rake generate` で DB を再生成しても `bitclust server` を
# 再起動しなくてよいようにする。
#
# テストリスト:
# [x] DB を再生成(rm_rf+init+update)した後、同じ App/Interface への同じ
#     リクエストで新しい内容が返り、古い内容(メモ化されていたはず)が消えて
#     いる(Rack ハンドラ、dbpath が String の単一 DB)
# [x] 同じことが WEBrick ハンドラ(options[:rack] を渡さない既定経路)でも
#     成り立つ
# [x] dbpath が Array(複数バージョン)のときも、各バージョンの Interface が
#     独立に再生成を検知する。片方だけ再生成しても、もう片方の内容は無関係
#     のまま
# [x] DB 再生成の途中(rm_rf 直後、properties が一時的に存在しない)に
#     リクエストが来ても例外にならず、直前の内容を返し続ける(次のリクエスト
#     で改めて判定する)
# [x] --capi 有効時は FunctionDatabase 側の再生成も反映される
class TestApp < Test::Unit::TestCase
  def setup
    $bitclust_context_cache = nil
    @tmpdir = Dir.mktmpdir('bitclust-app-reload')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    $bitclust_context_cache = nil
  end

  def test_rack_handler_reflects_regenerated_db_without_restart
    dbdir = "#{@tmpdir}/db"
    srcroot = "#{@tmpdir}/src"
    build_method_db(dbdir, srcroot, 'ORIGINAL_MARKER')

    interface = build_app(dbdir, :rack => true).interfaces['/view/']

    assert_include(rack_body(interface, '/class/Target'), 'ORIGINAL_MARKER')

    regenerate(dbdir) { build_method_db(dbdir, srcroot, 'UPDATED_MARKER') }

    after = rack_body(interface, '/class/Target')
    assert_include(after, 'UPDATED_MARKER')
    assert_not_include(after, 'ORIGINAL_MARKER')
  end

  def test_webrick_handler_reflects_regenerated_db_without_restart
    dbdir = "#{@tmpdir}/db"
    srcroot = "#{@tmpdir}/src"
    build_method_db(dbdir, srcroot, 'ORIGINAL_MARKER')

    servlet = build_app(dbdir).interfaces['/view/'].get_instance(WEBrick::Config::HTTP)

    assert_include(webrick_body(servlet, '/class/Target'), 'ORIGINAL_MARKER')

    regenerate(dbdir) { build_method_db(dbdir, srcroot, 'UPDATED_MARKER') }

    after = webrick_body(servlet, '/class/Target')
    assert_include(after, 'UPDATED_MARKER')
    assert_not_include(after, 'ORIGINAL_MARKER')
  end

  def test_each_version_reloads_independently_for_array_dbpath
    dbdir_30 = "#{@tmpdir}/db-3.0"
    dbdir_40 = "#{@tmpdir}/db-4.0"
    src_30 = "#{@tmpdir}/src-3.0"
    src_40 = "#{@tmpdir}/src-4.0"
    build_method_db(dbdir_30, src_30, 'V30_ORIGINAL')
    build_method_db(dbdir_40, src_40, 'V40_ORIGINAL')

    datadir = File.expand_path('../data/bitclust', __dir__)
    app = BitClust::App.new(
      :dbpath => [dbdir_30, dbdir_40],
      :rack => true,
      :baseurl => '',
      :capi => false,
      :encoding => 'utf-8',
      :datadir => datadir,
      :templatedir => "#{datadir}/template.offline"
    )
    interface_30 = app.interfaces['3.0']
    interface_40 = app.interfaces['4.0']

    assert_include(rack_body(interface_30, '/class/Target'), 'V30_ORIGINAL')
    assert_include(rack_body(interface_40, '/class/Target'), 'V40_ORIGINAL')

    regenerate(dbdir_30) { build_method_db(dbdir_30, src_30, 'V30_UPDATED') }

    v30_after = rack_body(interface_30, '/class/Target')
    assert_include(v30_after, 'V30_UPDATED')
    assert_not_include(v30_after, 'V30_ORIGINAL')
    # 触っていない 4.0 側は無関係のまま
    assert_include(rack_body(interface_40, '/class/Target'), 'V40_ORIGINAL')
  end

  def test_stale_content_served_without_raising_while_properties_missing
    dbdir = "#{@tmpdir}/db"
    srcroot = "#{@tmpdir}/src"
    build_method_db(dbdir, srcroot, 'ORIGINAL_MARKER')

    interface = build_app(dbdir, :rack => true).interfaces['/view/']
    assert_include(rack_body(interface, '/class/Target'), 'ORIGINAL_MARKER')

    # rake generate の rm_rf 直後(init/update が終わる前)を再現する: properties
    # が一時的に存在しない
    FileUtils.rm_rf(dbdir)

    assert_nothing_raised do
      during = rack_body(interface, '/class/Target')
      assert_include(during, 'ORIGINAL_MARKER')
    end

    regenerate(dbdir) { build_method_db(dbdir, srcroot, 'UPDATED_MARKER') }

    assert_include(rack_body(interface, '/class/Target'), 'UPDATED_MARKER')
  end

  def test_capi_function_database_also_reloads
    dbdir = "#{@tmpdir}/db"
    srcroot = "#{@tmpdir}/src"
    build_method_db(dbdir, srcroot, 'ORIGINAL_MARKER')
    build_function(dbdir, 'This is the original function doc.')

    interface = build_app(dbdir, :rack => true, :capi => true).interfaces['/view/']

    assert_include(rack_body(interface, '/function/public_func'), 'the original function doc')

    regenerate(dbdir) do
      build_method_db(dbdir, srcroot, 'UPDATED_MARKER')
      build_function(dbdir, 'This is the updated function doc.')
    end

    after = rack_body(interface, '/function/public_func')
    assert_include(after, 'the updated function doc')
    assert_not_include(after, 'the original function doc')
  end

  # rake generate の途中(init 後〜update 完了前)にリクエストが来ると、
  # init 時点の properties mtime で途中状態の DB を掴んで再構築してしまう。
  # update 完了(transaction の commit)時に properties の mtime が進むこと
  # により、次のリクエストで完成した DB を読み直して収束すること。
  # (utime による人工的な mtime 操作をせず、commit 側の touch だけに頼る)
  def test_request_during_regeneration_converges_after_update_completes
    dbdir = "#{@tmpdir}/db"
    srcroot = "#{@tmpdir}/src"
    build_method_db(dbdir, srcroot, 'ORIGINAL_MARKER')
    interface = build_app(dbdir, :rack => true).interfaces['/view/']
    assert_include(rack_body(interface, '/class/Target'), 'ORIGINAL_MARKER')

    # 再生成の途中状態を再現: rm_rf → init+propset まで(update はまだ)
    FileUtils.rm_rf(dbdir)
    db = BitClust::MethodDatabase.new(dbdir)
    db.init
    db.transaction do
      db.propset('version', '3.4')
      db.propset('encoding', 'utf-8')
    end
    # 途中状態のリクエストは(内容はともかく)例外にならないこと
    assert_nothing_raised { rack_body(interface, '/class/Target') }

    # update 完了 → 次のリクエストで新しい内容に収束すること
    File.write("#{srcroot}/testlib.rd", <<~RD)
      = class Target < Object
      UPDATED_MARKER

      == Instance Methods
      --- foo
      foo body
    RD
    db.transaction do
      db.update_by_stdlibtree(srcroot)
    end
    after = rack_body(interface, '/class/Target')
    assert_include(after, 'UPDATED_MARKER')
    assert_not_include(after, 'ORIGINAL_MARKER')
  end

  private

  # Screen#run_template は互換 ERB を self.class(ClassScreen 等)にキャッシュ
  # するため、同一プロセス内で異なる templatedir を混ぜて使うと「最初に
  # コンパイルされた方が以後ずっと勝つ」(test_method_screen.rb 冒頭のコメント
  # 参照)。このテストファイルはスイート内の他の Screen 系テストと同じ
  # template.offline に統一し、新たな衝突を持ち込まない
  def build_app(dbdir, extra = {})
    datadir = File.expand_path('../data/bitclust', __dir__)
    BitClust::App.new({
      :dbpath => dbdir,
      :viewpath => '/view/',
      :baseurl => '',
      :capi => false,
      :encoding => 'utf-8',
      :datadir => datadir,
      :templatedir => "#{datadir}/template.offline"
    }.merge(extra))
  end

  def rack_body(interface, path)
    env = Rack::MockRequest.env_for(path)
    _status, _headers, body = interface.call(env)
    body.join
  end

  def webrick_body(servlet, path)
    config = WEBrick::Config::HTTP
    wreq = WEBrick::HTTPRequest.new(config)
    wreq.parse(StringIO.new("GET #{path} HTTP/1.1\r\nHost: example.com\r\n\r\n"))
    wres = WEBrick::HTTPResponse.new(config)
    servlet.do_GET(wreq, wres)
    wres.body
  end

  # DB 再生成の前後で properties の mtime が必ず変わるようにする。
  # ファイルシステムの mtime 解像度(秒単位のものもある)に依存しないよう、
  # 再生成後に明示的に前より先の時刻へ File.utime で進める
  def regenerate(dbdir)
    properties_path = "#{dbdir}/properties"
    before = File.exist?(properties_path) ? File.mtime(properties_path) : nil
    yield
    forced = (before || Time.now) + 5
    File.utime(forced, forced, properties_path)
  end

  def build_method_db(dbdir, srcroot, marker)
    FileUtils.mkdir_p(srcroot)
    File.write("#{srcroot}/LIBRARIES", "testlib\n")
    File.write("#{srcroot}/testlib.rd", <<~RD)
      = class Target < Object
      #{marker}

      == Instance Methods
      --- foo
      foo body
    RD
    db = BitClust::MethodDatabase.new(dbdir)
    db.init
    db.transaction do
      db.propset('version', '3.4')
      db.propset('encoding', 'utf-8')
    end
    db.transaction do
      db.update_by_stdlibtree(srcroot)
    end
    db
  end

  def build_function(dbdir, doc)
    FileUtils.mkdir_p("#{dbdir}/function")
    File.write("#{dbdir}/function/public_func", <<~HERE)
      filename=test.c
      macro=false
      private=false
      type=VALUE
      name=public_func
      params=()


      #{doc}
    HERE
  end
end
