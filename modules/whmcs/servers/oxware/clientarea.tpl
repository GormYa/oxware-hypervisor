{if $error}
<div class="alert alert-danger"><strong>Hata:</strong> {$error}</div>
{else}
<style>
.oxw-panel { background:#0f1117; border:1px solid #2a2d3e; border-radius:10px; padding:20px; color:#e0e0e0; font-family:'Inter',sans-serif; }
.oxw-title { font-size:18px; font-weight:700; color:#fff; margin-bottom:16px; display:flex; align-items:center; gap:8px; }
.oxw-grid { display:grid; grid-template-columns:1fr 1fr; gap:12px; margin-bottom:16px; }
.oxw-card { background:#1a1d2e; border:1px solid #2a2d3e; border-radius:8px; padding:14px; }
.oxw-card-label { font-size:11px; text-transform:uppercase; letter-spacing:.05em; color:#6b7280; margin-bottom:4px; }
.oxw-card-value { font-size:15px; font-weight:600; color:#fff; word-break:break-all; }
.oxw-card-value.green  { color:#10b981; }
.oxw-card-value.red    { color:#ef4444; }
.oxw-card-value.yellow { color:#f59e0b; }
.oxw-cred { background:#1a1d2e; border:1px solid #2a2d3e; border-radius:8px; padding:14px; margin-bottom:12px; }
.oxw-cred-row { display:flex; align-items:center; justify-content:space-between; margin-bottom:8px; }
.oxw-cred-row:last-child { margin-bottom:0; }
.oxw-copy { background:#2a2d3e; border:none; border-radius:4px; color:#9ca3af; font-size:11px; padding:3px 8px; cursor:pointer; }
.oxw-copy:hover { background:#3a3d4e; color:#fff; }
.oxw-blur { filter:blur(4px); transition:filter .2s; cursor:pointer; user-select:none; }
.oxw-blur:hover { filter:none; }
.oxw-bar { background:#2a2d3e; border-radius:4px; height:6px; overflow:hidden; margin-top:6px; }
.oxw-bar-fill { height:100%; border-radius:4px; transition:width .6s; }
.oxw-console-btn { display:inline-flex; align-items:center; gap:6px; background:#6366f1; color:#fff; border:none; border-radius:6px; padding:10px 18px; font-size:13px; font-weight:600; cursor:pointer; text-decoration:none; margin-top:4px; }
.oxw-console-btn:hover { background:#4f46e5; color:#fff; text-decoration:none; }
.oxw-status-dot { width:8px; height:8px; border-radius:50%; display:inline-block; margin-right:4px; }
.oxw-section-title { font-size:13px; font-weight:600; color:#9ca3af; text-transform:uppercase; letter-spacing:.05em; margin:16px 0 8px; }
</style>

<div class="oxw-panel">
  <div class="oxw-title">
    <svg width="18" height="18" fill="none" viewBox="0 0 24 24" stroke="currentColor" style="color:#6366f1"><rect x="2" y="3" width="20" height="14" rx="2" stroke-width="2"/><path d="M8 21h8M12 17v4" stroke-width="2" stroke-linecap="round"/></svg>
    {$vm_name}
    {if $vm_status == 'running'}
      <span class="oxw-status-dot" style="background:#10b981"></span><span style="color:#10b981;font-size:13px;">Çalışıyor</span>
    {elseif $vm_status == 'stopped'}
      <span class="oxw-status-dot" style="background:#ef4444"></span><span style="color:#ef4444;font-size:13px;">Durduruldu</span>
    {else}
      <span class="oxw-status-dot" style="background:#f59e0b"></span><span style="color:#f59e0b;font-size:13px;">{$vm_status}</span>
    {/if}
  </div>

  <!-- IP Bilgisi -->
  <div class="oxw-section-title">Ağ Bilgisi</div>
  <div class="oxw-grid">
    <div class="oxw-card">
      <div class="oxw-card-label">IP Adresi</div>
      <div class="oxw-card-value">{$vm_ip}</div>
    </div>
    {if $vm_public_ip && $vm_public_ip != $vm_ip}
    <div class="oxw-card">
      <div class="oxw-card-label">Public IP</div>
      <div class="oxw-card-value green">{$vm_public_ip}</div>
    </div>
    {/if}
    {if $vm_int_ip}
    <div class="oxw-card">
      <div class="oxw-card-label">Dahili IP</div>
      <div class="oxw-card-value">{$vm_int_ip}</div>
    </div>
    {/if}
    <div class="oxw-card">
      <div class="oxw-card-label">VM ID</div>
      <div class="oxw-card-value" style="font-size:11px;color:#6b7280;">{$vm_id}</div>
    </div>
  </div>

  <!-- Kullanici Bilgileri -->
  <div class="oxw-section-title">Erişim Bilgileri</div>
  <div class="oxw-cred">
    <div class="oxw-cred-row">
      <div>
        <div class="oxw-card-label">Kullanıcı Adı</div>
        <div class="oxw-card-value">{$ssh_user}</div>
      </div>
      <button class="oxw-copy" onclick="navigator.clipboard.writeText('{$ssh_user}');this.textContent='Kopyalandı!';setTimeout(()=>this.textContent='Kopyala',2000)">Kopyala</button>
    </div>
    <div class="oxw-cred-row">
      <div>
        <div class="oxw-card-label">Şifre <span style="font-size:10px;color:#6b7280">(görmek için tıkla)</span></div>
        <div class="oxw-card-value oxw-blur" onclick="this.classList.toggle('oxw-blur')">{$ssh_pass}</div>
      </div>
      <button class="oxw-copy" onclick="navigator.clipboard.writeText('{$ssh_pass}');this.textContent='Kopyalandı!';setTimeout(()=>this.textContent='Kopyala',2000)">Kopyala</button>
    </div>
    <div class="oxw-cred-row">
      <div>
        <div class="oxw-card-label">IP / Host</div>
        <div class="oxw-card-value">{$vm_ip}</div>
      </div>
      <button class="oxw-copy" onclick="navigator.clipboard.writeText('{$vm_ip}');this.textContent='Kopyalandı!';setTimeout(()=>this.textContent='Kopyala',2000)">Kopyala</button>
    </div>
  </div>

  <!-- Kaynak Kullanimi -->
  <div class="oxw-section-title">Kaynak Kullanımı</div>
  <div class="oxw-grid">
    <div class="oxw-card">
      <div class="oxw-card-label">CPU Kullanımı</div>
      <div class="oxw-card-value">{$vm_cpu}%</div>
      <div class="oxw-bar"><div class="oxw-bar-fill" style="width:{$vm_cpu}%;background:{if $vm_cpu > 90}#ef4444{elseif $vm_cpu > 70}#f59e0b{else}#6366f1{/if}"></div></div>
    </div>
    <div class="oxw-card">
      <div class="oxw-card-label">RAM Kullanımı</div>
      <div class="oxw-card-value">{$vm_ram}%</div>
      <div class="oxw-bar"><div class="oxw-bar-fill" style="width:{$vm_ram}%;background:{if $vm_ram > 90}#ef4444{elseif $vm_ram > 70}#f59e0b{else}#10b981{/if}"></div></div>
    </div>
    <div class="oxw-card">
      <div class="oxw-card-label">Disk Kullanımı</div>
      <div class="oxw-card-value">{$vm_disk} GB</div>
    </div>
    {if $vm_ram_total}
    <div class="oxw-card">
      <div class="oxw-card-label">Toplam RAM</div>
      <div class="oxw-card-value">{$vm_ram_total} MB</div>
    </div>
    {/if}
  </div>

  <!-- Console -->
  {if $console_url}
  <div class="oxw-section-title">Konsol</div>
  <a href="{$console_url}" target="_blank" class="oxw-console-btn">
    <svg width="14" height="14" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>
    Web Konsolu Aç (noVNC)
  </a>
  <p style="font-size:11px;color:#6b7280;margin-top:6px;">Link 5 dakika geçerlidir. Her sayfada yenilenir.</p>
  {/if}
</div>
{/if}
