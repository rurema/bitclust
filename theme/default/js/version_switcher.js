// Version switcher for statichtml pages served under a /ja/<version>/ tree.
//
// Renders a <select> into the #version-switcher slot in the top bar. Picking
// a version navigates to the same page under that version; if the page does
// not exist there, it falls back to the newest version that has it, and as a
// last resort to that version's top page. On the first interaction every
// other version is probed with a HEAD request and missing ones are disabled.
//
// Pages not served under a versioned path (local previews, /ja/search/) get
// no switcher: attach() is a no-op there.
(function () {
  'use strict';

  // 公開済みの版(新しい順)。doctree の Rakefile の
  // SUPPORTED_VERSIONS / OLD_VERSIONS と揃える。
  var RELEASED_VERSIONS = [
    '4.0', '3.4', '3.3', '3.2', '3.1', '3.0',
    '2.7.0', '2.6.0', '2.5.0', '2.4.0', '2.3.0', '2.2.0', '2.1.0', '2.0.0',
    '1.9.3', '1.8.7'
  ];
  var EDGE_VERSION = 'master';
  var ALIASES = ['latest', EDGE_VERSION];

  function knownVersion(version) {
    return RELEASED_VERSIONS.indexOf(version) !== -1 ||
      ALIASES.indexOf(version) !== -1;
  }

  function parsePath(pathname) {
    var m = /^(.*\/ja\/)([^\/]+)(\/.+)$/.exec(pathname);
    if (!m || !knownVersion(m[2])) return null;
    return { base: m[1], version: m[2], rest: m[3] };
  }

  function targetUrl(parsed, version) {
    return parsed.base + version + parsed.rest;
  }

  function optionVersions(currentVersion) {
    var versions = [EDGE_VERSION].concat(RELEASED_VERSIONS);
    if (versions.indexOf(currentVersion) === -1) {
      versions.unshift(currentVersion);
    }
    return versions;
  }

  // true: exists / false: does not exist / null: unknown (network error)
  function checkExists(url) {
    return fetch(url, { method: 'HEAD' })
      .then(function (res) { return res.ok; })
      .catch(function () { return null; });
  }

  // Resolve where picking `version` should go. Unknown existence keeps the
  // target so an offline or CORS-restricted page still just navigates.
  function resolveTarget(parsed, version, exists) {
    var target = targetUrl(parsed, version);
    return exists(target).then(function (ok) {
      if (ok !== false) return target;
      var candidates = RELEASED_VERSIONS.filter(function (v) {
        return v !== version;
      });
      var tryNext = function (i) {
        if (i >= candidates.length) return parsed.base + version + '/';
        var url = targetUrl(parsed, candidates[i]);
        return exists(url).then(function (found) {
          return found === true ? url : tryNext(i + 1);
        });
      };
      return tryNext(0);
    });
  }

  function attach(deps) {
    var doc = deps.document;
    var slot = doc.getElementById('version-switcher');
    var parsed = parsePath(deps.location.pathname);
    if (!slot || !parsed) return false;
    var exists = deps.checkExists || checkExists;

    var select = doc.createElement('select');
    select.setAttribute('aria-label', '他のバージョンの同じページを表示');
    optionVersions(parsed.version).forEach(function (version) {
      var option = doc.createElement('option');
      option.value = version;
      option.textContent = version;
      option.selected = version === parsed.version;
      select.appendChild(option);
    });
    select.value = parsed.version;

    var probed = false;
    var probe = function () {
      if (probed) return;
      probed = true;
      Array.prototype.forEach.call(select.children, function (option) {
        if (option.value === parsed.version) return;
        exists(targetUrl(parsed, option.value)).then(function (ok) {
          if (ok === false) option.disabled = true;
        });
      });
    };
    select.addEventListener('focus', probe);
    select.addEventListener('mousedown', probe);
    select.addEventListener('touchstart', probe);

    select.addEventListener('change', function () {
      var version = select.value;
      if (version === parsed.version) return;
      resolveTarget(parsed, version, exists).then(function (url) {
        deps.setHref(url);
      });
    });

    slot.appendChild(select);
    return true;
  }

  var api = {
    RELEASED_VERSIONS: RELEASED_VERSIONS,
    EDGE_VERSION: EDGE_VERSION,
    parsePath: parsePath,
    targetUrl: targetUrl,
    optionVersions: optionVersions,
    checkExists: checkExists,
    resolveTarget: resolveTarget,
    attach: attach
  };
  if (typeof globalThis !== 'undefined') {
    globalThis.RuremaVersionSwitcher = api;
  }

  if (typeof document !== 'undefined' && typeof location !== 'undefined') {
    var init = function () {
      attach({
        document: document,
        location: location,
        setHref: function (url) { location.href = url; }
      });
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', init);
    } else {
      init();
    }
  }
})();
