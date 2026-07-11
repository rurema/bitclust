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

        // COPY button
        const btn = document.createElement('span')
        btn.setAttribute('class', 'highlight__copy-button')
        elem.insertBefore(btn, elem.firstChild)

        btn.onclick = function(){
          writeClipboard(text).then(function() {
            btn.classList.add("copied")
            window.setTimeout(function() { btn.classList.remove("copied") }, 1000)
          }).catch(function() {
            // コピー失敗時は従来どおり何も表示しない
          })
        }
      }
    )
  }
})()
