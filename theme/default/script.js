(function() {
  // クリップボードへのコピー。Clipboard API が使えない環境
  // (非セキュアコンテキストや古いブラウザ)では従来の
  // textarea + execCommand にフォールバックする
  function writeClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text)
    }
    return new Promise(function(resolve, reject) {
      const textarea = document.createElement('textarea')
      textarea.setAttribute('class', 'highlight__copy-text')
      textarea.value = text
      document.body.appendChild(textarea)
      textarea.select()
      const ok = document.execCommand('copy')
      document.body.removeChild(textarea)
      if (ok) {
        resolve()
      } else {
        reject(new Error('copy command failed'))
      }
    })
  }

  function hasClass(elem, name) {
    return Boolean(elem && elem.className &&
      String(elem.className).split(' ').indexOf(name) >= 0)
  }

  function findChildByClass(elem, name) {
    const children = elem.children
    for (let i = 0; i < children.length; i++) {
      if (hasClass(children[i], name)) return children[i]
    }
    return null
  }

  // elem(pre)の直前にツールバー行 <div class="highlight__toolbar"> を
  // 用意し、その右端のボタン置き場(highlight__button-group)を返す。
  // ボタンを pre の中に float させる方式は、カーソル形状のちらつき・
  // 編集時のレイアウト崩れ・pre の上 padding を 0 にする必要など無理が
  // 多かったため、pre の外に出している。コンパイラが pre の直前に置く
  // caption(タブ)があればツールバー左端に取り込み、pre への密着を保つ。
  // js/run.js も同じボタン置き場に RUN ボタンを入れる
  function buttonGroup(elem) {
    const prev = elem.previousElementSibling
    if (hasClass(prev, 'highlight__toolbar')) {
      return findChildByClass(prev, 'highlight__button-group')
    }
    const toolbar = document.createElement('div')
    toolbar.setAttribute('class', 'highlight__toolbar')
    const group = document.createElement('span')
    group.setAttribute('class', 'highlight__button-group')
    if (hasClass(prev, 'caption')) {
      elem.parentNode.insertBefore(toolbar, prev)
      toolbar.appendChild(prev) // caption をタブとして左端へ移動
    } else {
      elem.parentNode.insertBefore(toolbar, elem)
    }
    toolbar.appendChild(group)
    return group
  }

  // elem の直前のツールバーに COPY ボタンを付ける。getText はクリック時に
  // 評価されるので、RUN の実行結果のように内容が変わる要素にも使える。
  // elem は DOM ツリーに挿入済みであること(直前にツールバーを差し込む)
  function addCopyButton(elem, getText) {
    const btn = document.createElement('span')
    btn.setAttribute('class', 'highlight__copy-button')
    btn.onclick = function(){
      writeClipboard(getText()).then(function() {
        btn.classList.add("copied")
        window.setTimeout(function() { btn.classList.remove("copied") }, 1000)
      }).catch(function() {
        // コピー失敗時は従来どおり何も表示しない
      })
    }
    // COPY は常にグループ右端(RUN は run.js が先頭に prepend する)
    buttonGroup(elem).appendChild(btn)
    return btn
  }

  // RUN 出力(js/run.js)など、後から動的に生成される pre 用の公開フック
  window.ruremaAddCopyButton = addCopyButton

  window.onload = function() {
    // 言語指定なしのコードブロックは class を持たない素の <pre> になるため、
    // highlight クラスではなく pre 要素全体に COPY ボタンを付ける
    const elems = document.querySelectorAll('pre')

    let tempDiv = document.createElement('div')

    Array.prototype.forEach.call(elems,
      function(elem) {
        // sample code without caption
        tempDiv.innerHTML = elem.innerHTML
        const caption = tempDiv.getElementsByClassName("caption")[0]
        if (caption) tempDiv.removeChild(caption)

        // RUN ボタンでサンプルを編集しても COPY は元のテキストを保持する
        const text = tempDiv.textContent.replace(/^\n+/, "").replace(/\n{2,}$/, "\n")

        addCopyButton(elem, function() { return text })
      }
    )
  }
})()
