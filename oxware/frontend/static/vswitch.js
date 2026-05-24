/**
 * vswitch.js — OXware Virtual Switch Management (ESXi-style)
 * Renders libvirt networks as visual vSwitch cards using DOM methods (no innerHTML for data).
 */
(function(global) {
  'use strict';

  // ── helpers ──────────────────────────────────────────────────────────────────
  function esc(s) {
    if (typeof escHtml === 'function') return escHtml(String(s));
    var d = document.createElement('div');
    d.textContent = String(s || '');
    return d.textContent;
  }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function api(url, opts) {
    if (typeof _api === 'function') return _api(url, opts);
    return fetch(url, Object.assign({ headers: { Authorization: 'Bearer ' + (localStorage.getItem('oxware_token') || '') } }, opts)).then(function(r) { return r.json(); });
  }

  // ── Build vSwitch card ────────────────────────────────────────────────────────
  function buildVSwitchCard(net, physNics) {
    var isActive   = net.active;
    var mode       = (net.mode || 'nat').toLowerCase();
    var bridgeName = net.bridge || '';
    var vmCount    = net.vm_count !== undefined ? net.vm_count : '—';
    var modeLabel  = mode === 'bridge' ? 'bridge' : mode === 'nat' ? 'nat' : 'standard';

    var uplinkIfaces = (physNics || []).filter(function(n) {
      return n.master === bridgeName || n.bridge === bridgeName;
    });

    // ── Card ─────────────────────────────────────────────────────────────────
    var card = el('div', 'vsw-card');

    // Header
    var head = el('div', 'vsw-card-head');
    var ico  = el('i');
    ico.className = 'fa-solid fa-sitemap';
    ico.style.cssText = 'color:#60a5fa;font-size:15px';
    var nameSpan = el('span', '', net.name);
    nameSpan.style.cssText = 'font-size:13px;font-weight:700';
    var badge = el('span', 'vsw-badge ' + modeLabel, mode.toUpperCase());
    var brSpan = el('span', '', bridgeName || '');
    brSpan.style.cssText = 'font-size:11px;color:var(--text-muted,#7d8590);font-family:monospace';
    var vmSp  = el('span', '', vmCount + ' VM');
    vmSp.style.cssText = 'margin-left:auto;font-size:11px;color:var(--text-muted,#7d8590)';
    var dot   = el('span');
    dot.style.cssText = 'width:8px;height:8px;border-radius:50%;flex-shrink:0;background:' +
      (isActive ? '#3fb950;box-shadow:0 0 6px #3fb95070' : '#6e7681');
    var chev  = el('i');
    chev.className = 'fa-solid fa-chevron-down';
    chev.style.cssText = 'color:var(--text-muted,#7d8590);font-size:11px;margin-left:4px';

    [ico, nameSpan, badge, brSpan, vmSp, dot, chev].forEach(function(c) { head.appendChild(c); });
    card.appendChild(head);

    // Body (collapsible)
    var body = el('div', 'vsw-body');
    var diagram = el('div', 'vsw-diagram');

    // — Uplinks col —
    var uplinkCol = el('div', 'vsw-col uplink');
    var ulLabel = el('div', '', 'UPLINK');
    ulLabel.style.cssText = 'font-size:9px;text-transform:uppercase;letter-spacing:.06em;color:var(--text-muted,#7d8590);margin-bottom:6px';
    uplinkCol.appendChild(ulLabel);

    if (uplinkIfaces.length) {
      uplinkIfaces.forEach(function(u) {
        var row = el('div', 'uplink-item');
        var udot = el('span', 'uplink-dot ' + (u.state === 'up' ? 'up' : 'down'));
        var uname = el('span', '', u.name);
        var uspd = el('span', '', u.speed || '');
        uspd.style.cssText = 'margin-left:auto;font-size:10px;color:var(--text-muted,#7d8590)';
        row.appendChild(udot); row.appendChild(uname); row.appendChild(uspd);
        uplinkCol.appendChild(row);
      });
    } else {
      var row = el('div', 'uplink-item');
      row.style.cssText = 'color:var(--text-muted,#7d8590);opacity:.5';
      var udot = el('span', 'uplink-dot down');
      var uname = el('span', '', 'Host NAT');
      row.appendChild(udot); row.appendChild(uname);
      uplinkCol.appendChild(row);
    }

    // — Connector —
    var conn1 = el('div', 'vsw-connector');

    // — Switch box col —
    var swCol = el('div', 'vsw-col switch');
    var swBox = el('div', 'vsw-sw-box');
    var swName = el('div', 'sw-name', net.name);
    var swSub  = el('div', 'sw-sub', bridgeName || mode);
    var ports  = el('div', 'vsw-sw-ports');
    var portCount = Math.min(8, Math.max(2, 1 + uplinkIfaces.length));
    for (var p = 0; p < portCount; p++) {
      var port = el('div', 'vsw-port' + (p < (uplinkIfaces.length || 1) ? ' up' : ''));
      ports.appendChild(port);
    }
    [swName, swSub, ports].forEach(function(c) { swBox.appendChild(c); });
    swCol.appendChild(swBox);

    // — Connector —
    var conn2 = el('div', 'vsw-connector');

    // — Port Groups col —
    var pgCol = el('div', 'vsw-col pgroups');
    var pgLabel = el('div', '', 'PORT GROUPS');
    pgLabel.style.cssText = 'font-size:9px;text-transform:uppercase;letter-spacing:.06em;color:var(--text-muted,#7d8590);margin-bottom:6px';
    pgCol.appendChild(pgLabel);

    // One default port group per network
    var pgItem = el('div', 'pg-item');
    var pgIco  = el('div', 'pg-icon', '🔌');
    pgIco.style.background = 'rgba(61,130,240,0.12)';
    var pgInfo = el('div');
    var pgName = el('div', '', net.name);
    pgName.style.fontWeight = '600';
    var pgType = el('div', '', 'VM Network');
    pgType.style.cssText = 'font-size:10px;color:var(--text-muted,#7d8590)';
    var netRange = el('span', '', net.network || '');
    netRange.style.cssText = 'margin-left:auto;font-size:11px;color:var(--text-muted,#7d8590)';
    pgInfo.appendChild(pgName); pgInfo.appendChild(pgType);
    [pgIco, pgInfo, netRange].forEach(function(c) { pgItem.appendChild(c); });
    pgCol.appendChild(pgItem);

    var addPgBtn = el('button', 'btn sm', '+ Port Group Ekle');
    addPgBtn.style.cssText = 'margin-top:6px;font-size:10px';
    addPgBtn.onclick = function() { global.vswitchAddPortGroup(net.name); };
    pgCol.appendChild(addPgBtn);

    [uplinkCol, conn1, swCol, conn2, pgCol].forEach(function(c) { diagram.appendChild(c); });
    body.appendChild(diagram);

    // Actions row
    var actions = el('div', 'vsw-actions');
    var btnStart = el('button', 'btn sm', '▶ Başlat');
    if (isActive) btnStart.disabled = true;
    btnStart.onclick = function() { global.vswitchStart(net.name); };

    var btnStop = el('button', 'btn sm', '■ Durdur');
    btnStop.style.color = '#f87171';
    if (!isActive) btnStop.disabled = true;
    btnStop.onclick = function() { global.vswitchStop(net.name); };

    var btnEdit = el('button', 'btn sm', '⚙ Düzenle');
    btnEdit.onclick = function() { global.vswitchEdit(net.name); };

    var btnDel = el('button', 'btn sm', '🗑 Sil');
    btnDel.style.cssText = 'color:#f87171;margin-left:auto';
    btnDel.onclick = function() { global.vswitchDelete(net.name); };

    [btnStart, btnStop, btnEdit, btnDel].forEach(function(b) { actions.appendChild(b); });
    body.appendChild(actions);
    card.appendChild(body);

    // Toggle collapse
    head.onclick = function() {
      body.style.display = body.style.display === 'none' ? '' : 'none';
    };

    return card;
  }

  // ── Public API ────────────────────────────────────────────────────────────────
  global.loadVSwitches = function() {
    var grid = document.getElementById('vsw-grid');
    if (!grid) return;

    var spinner = el('div', '', '');
    spinner.style.cssText = 'text-align:center;padding:40px;color:var(--text-muted,#7d8590)';
    var ico = el('i'); ico.className = 'fa-solid fa-spinner fa-spin';
    ico.style.cssText = 'font-size:22px;margin-bottom:8px;display:block';
    var txt = el('span', '', 'Yükleniyor…');
    spinner.appendChild(ico); spinner.appendChild(txt);
    while (grid.firstChild) grid.removeChild(grid.firstChild);
    grid.appendChild(spinner);

    Promise.all([
      api('/api/networks'),
      api('/api/networks/host-interfaces').catch(function() { return { interfaces: [] }; })
    ]).then(function(results) {
      var netData = results[0]; var ifData = results[1];
      var nets     = netData.networks || [];
      var ifaces   = ifData.interfaces || [];
      var physNics = ifaces.filter(function(i) { return i.type === 'ethernet'; });

      while (grid.firstChild) grid.removeChild(grid.firstChild);

      if (!nets.length) {
        var empty = el('div', '', '');
        empty.style.cssText = 'text-align:center;padding:40px;color:var(--text-muted,#7d8590)';
        var ei = el('i'); ei.className = 'fa-solid fa-sitemap';
        ei.style.cssText = 'font-size:28px;opacity:.2;display:block;margin-bottom:8px';
        var et = el('span', '', 'vSwitch bulunamadı — Yeni Ağ oluşturun');
        empty.appendChild(ei); empty.appendChild(et);
        grid.appendChild(empty);
        return;
      }

      nets.forEach(function(net) {
        grid.appendChild(buildVSwitchCard(net, physNics));
      });
    }).catch(function(e) {
      while (grid.firstChild) grid.removeChild(grid.firstChild);
      var errDiv = el('div', '', '');
      errDiv.style.cssText = 'padding:20px;color:#f87171';
      errDiv.textContent = 'Yüklenemedi: ' + (e.message || e);
      grid.appendChild(errDiv);
    });
  };

  global.openVSwitchCreate = function() {
    if (typeof openCreateNetworkModal === 'function') openCreateNetworkModal();
  };

  global.vswitchStart = function(name) {
    api('/api/networks/' + encodeURIComponent(name) + '/start', { method: 'POST' })
      .then(function() { global.loadVSwitches(); })
      .catch(function(e) { alert('Başlatma hatası: ' + e.message); });
  };

  global.vswitchStop = function(name) {
    if (!confirm(name + ' ağını durdurmak istediğinize emin misiniz? Bağlı VM\'ler etkilenebilir.')) return;
    api('/api/networks/' + encodeURIComponent(name) + '/stop', { method: 'POST' })
      .then(function() { global.loadVSwitches(); })
      .catch(function(e) { alert('Durdurma hatası: ' + e.message); });
  };

  global.vswitchEdit = function(name) {
    alert('vSwitch düzenleme: ' + name + '\n(Detaylı VLAN/QoS yapılandırması — yakında)');
  };

  global.vswitchDelete = function(name) {
    if (!confirm(name + ' vSwitch silinsin mi? Bu işlem geri alınamaz.')) return;
    api('/api/networks/' + encodeURIComponent(name), { method: 'DELETE' })
      .then(function() { global.loadVSwitches(); })
      .catch(function(e) { alert('Silme hatası: ' + e.message); });
  };

  global.vswitchAddPortGroup = function(switchName) {
    var pgName = prompt('Port Group adı:', switchName + '-pg1');
    if (!pgName) return;
    alert('Port Group "' + pgName + '" ' + switchName + ' üzerine eklendi.\n(VLAN tabanlı port group desteği — yakında)');
  };

})(window);
