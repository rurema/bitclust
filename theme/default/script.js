(function() {
  window.onload = function() {
    const elems = document.getElementsByClassName('highlight')

    let backet = document.createElement('div')

    Array.prototype.forEach.call(elems,
      function(elem) {
        // sample code without caption
        backet.innerHTML = elem.innerHTML
        const caption = backet.getElementsByClassName("caption")[0]
        if (caption) backet.removeChild(caption)

        // textarea for preserving the copy text
        const copyText = document.createElement('textarea')
        copyText.setAttribute('class', 'highlight__copy-text')
        copyText.innerHTML = backet.textContent.replace(/^\n+/, "").replace(/\n{2,}$/, "\n")
        elem.appendChild(copyText)

        // COPY button
        const btn = document.createElement('div')
        btn.setAttribute('class', 'highlight__copy-button')
        btn.textContent = "COPY"
        elem.insertBefore(btn, elem.firstChild)

        btn.onclick = function(){
          copyText.select()
          document.execCommand("copy")
          alert("Copied to your Clipboard.")
        }
      }
    )
  }
})()
