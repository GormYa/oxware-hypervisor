<?php
/**
 * OXware Hypervisor — WHMCS Server Module
 * Versiyon: 1.0.0
 *
 * Kurulum:
 *   Bu klasörü WHMCS'in modules/servers/ dizinine kopyalayın:
 *     modules/servers/oxware/
 *   Ardından: WHMCS Admin → Kurulum → Sunucular → Yeni Sunucu → Tip: OXware
 *
 * Sunucu ayarları (WHMCS Admin → Kurulum → Sunucular):
 *   Hostname    : OXware API URL (ör: https://oxware.example.com)
 *   Access Hash : OXware API anahtarı (oxw_... ile başlar)
 *
 * Ürün yapılandırma seçenekleri (Configurable Options):
 *   CPU (vCPU), RAM (MB), Disk (GB), OS Template, Network
 */

if (!defined("WHMCS")) {
    die("Bu dosya doğrudan çalıştırılamaz.");
}

// ── Metadata ─────────────────────────────────────────────────────────────────

function oxware_MetaData()
{
    return [
        'DisplayName'    => 'OXware Hypervisor',
        'APIVersion'     => '1.1',
        'RequiresServer' => true,
    ];
}

// ── Ürün yapılandırma seçenekleri ────────────────────────────────────────────

function oxware_ConfigOptions()
{
    return [
        'CPU (vCPU)' => [
            'Type'        => 'text',
            'Size'        => 5,
            'Default'     => '2',
            'Description' => 'Sanal CPU sayısı (1-256)',
        ],
        'RAM (MB)' => [
            'Type'        => 'text',
            'Size'        => 8,
            'Default'     => '2048',
            'Description' => 'Bellek (MB) — ör: 2048 = 2 GB',
        ],
        'Disk (GB)' => [
            'Type'        => 'text',
            'Size'        => 8,
            'Default'     => '50',
            'Description' => 'Disk alanı (GB)',
        ],
        'OS Template' => [
            'Type'        => 'text',
            'Size'        => 30,
            'Default'     => 'ubuntu-22.04',
            'Description' => 'OXware template ID (ör: ubuntu-22.04, debian-12)',
        ],
        'Network' => [
            'Type'        => 'text',
            'Size'        => 20,
            'Default'     => 'default',
            'Description' => 'Libvirt ağ adı',
        ],
    ];
}

// ── Yardımcı: OXware REST API çağrısı ────────────────────────────────────────

function _oxware_api($params, $method, $endpoint, $body = null)
{
    $base = rtrim($params['serverhostname'], '/');
    $key  = trim($params['serveraccesshash']);

    $ch = curl_init($base . '/api' . $endpoint);
    $headers = [
        'Content-Type: application/json',
        'X-API-Key: ' . $key,
    ];

    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 30,
        CURLOPT_CUSTOMREQUEST  => strtoupper($method),
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_SSL_VERIFYHOST => false,
    ]);

    if ($body !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
    }

    $raw       = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curl_err  = curl_error($ch);
    curl_close($ch);

    if ($raw === false) {
        return ['error' => 'cURL hatası: ' . $curl_err];
    }

    $data = json_decode($raw, true);

    if ($http_code >= 400) {
        return ['error' => ($data['error'] ?? "HTTP $http_code")];
    }

    return $data ?? [];
}

function _oxware_vm_id($params)
{
    // VM ID, CreateAccount sırasında username alanına kaydedilir
    return $params['username'] ?? '';
}

// ── CreateAccount ─────────────────────────────────────────────────────────────

function oxware_CreateAccount($params)
{
    $cfg   = $params['configoptions'];
    $svcid = $params['serviceid'];
    $name  = 'vm-' . $svcid . '-' . preg_replace('/[^a-z0-9\-]/', '', strtolower($params['domain'] ?? 'svc'));

    $body = [
        'name'        => $name,
        'cpu'         => (int)($cfg['CPU (vCPU)'] ?? 2),
        'ram_mb'      => (int)($cfg['RAM (MB)'] ?? 2048),
        'disk_gb'     => (int)($cfg['Disk (GB)'] ?? 50),
        'os_template' => $cfg['OS Template'] ?? 'ubuntu-22.04',
        'network'     => $cfg['Network'] ?? 'default',
        'auto_start'  => true,
    ];

    $result = _oxware_api($params, 'POST', '/provision/create', $body);

    if (!empty($result['error'])) {
        return 'error: ' . $result['error'];
    }

    $vm_id = $result['vm']['id'] ?? $result['vm_id'] ?? '';
    $ip    = $result['vm']['ip']
          ?? ($result['vm']['networks'][0]['ip'] ?? '')
          ?: '';

    if (!$vm_id) {
        return 'error: VM ID alınamadı';
    }

    // VM ID'yi WHMCS servis alanına kaydet
    localAPI('UpdateClientProduct', [
        'serviceid' => $svcid,
        'username'  => $vm_id,
    ]);

    if ($ip) {
        localAPI('UpdateClientProduct', [
            'serviceid'  => $svcid,
            'dedicatedip' => $ip,
        ]);
    }

    return 'success';
}

// ── SuspendAccount ────────────────────────────────────────────────────────────

function oxware_SuspendAccount($params)
{
    $vm_id = _oxware_vm_id($params);
    if (!$vm_id) return 'error: VM ID bulunamadı';

    $result = _oxware_api($params, 'POST', "/provision/$vm_id/suspend");
    return !empty($result['error']) ? 'error: ' . $result['error'] : 'success';
}

// ── UnsuspendAccount ──────────────────────────────────────────────────────────

function oxware_UnsuspendAccount($params)
{
    $vm_id = _oxware_vm_id($params);
    if (!$vm_id) return 'error: VM ID bulunamadı';

    $result = _oxware_api($params, 'POST', "/provision/$vm_id/unsuspend");
    return !empty($result['error']) ? 'error: ' . $result['error'] : 'success';
}

// ── TerminateAccount ──────────────────────────────────────────────────────────

function oxware_TerminateAccount($params)
{
    $vm_id = _oxware_vm_id($params);
    if (!$vm_id) return 'success'; // Zaten silinmiş

    $result = _oxware_api($params, 'DELETE', "/provision/$vm_id");
    return !empty($result['error']) ? 'error: ' . $result['error'] : 'success';
}

// ── ChangePackage ─────────────────────────────────────────────────────────────

function oxware_ChangePackage($params)
{
    $vm_id = _oxware_vm_id($params);
    if (!$vm_id) return 'error: VM ID bulunamadı';

    $cfg  = $params['configoptions'];
    $body = [
        'cpu'     => (int)($cfg['CPU (vCPU)'] ?? 2),
        'ram_mb'  => (int)($cfg['RAM (MB)'] ?? 2048),
        'disk_gb' => (int)($cfg['Disk (GB)'] ?? 50),
    ];

    $result = _oxware_api($params, 'PUT', "/provision/$vm_id/resize", $body);
    return !empty($result['error']) ? 'error: ' . $result['error'] : 'success';
}

// ── TestConnection ────────────────────────────────────────────────────────────

function oxware_TestConnection($params)
{
    $result = _oxware_api($params, 'GET', '/system/stats');

    if (!empty($result['error'])) {
        return [
            'success' => false,
            'error'   => $result['error'],
        ];
    }

    return ['success' => true, 'error' => ''];
}

// ── ClientArea ────────────────────────────────────────────────────────────────

function oxware_ClientArea($params)
{
    $vm_id = _oxware_vm_id($params);

    if (!$vm_id) {
        return [
            'templatefile' => 'clientarea',
            'vars'         => ['error' => 'VM henüz oluşturulmadı.'],
        ];
    }

    $status   = _oxware_api($params, 'GET', "/provision/$vm_id/status");
    $base_url = rtrim($params['serverhostname'], '/');

    return [
        'templatefile' => 'clientarea',
        'vars'         => [
            'vm_id'      => $vm_id,
            'vm_name'    => $status['name']        ?? '—',
            'vm_status'  => $status['status']      ?? 'unknown',
            'vm_ip'      => $status['ip']          ?? '—',
            'vm_cpu'     => $status['cpu_percent'] ?? 0,
            'vm_ram'     => $status['mem_percent'] ?? 0,
            'base_url'   => $base_url,
            'error'      => $status['error']       ?? '',
        ],
    ];
}

// ── GetUsage ──────────────────────────────────────────────────────────────────

function oxware_GetUsage($params)
{
    $vm_id = _oxware_vm_id($params);
    if (!$vm_id) return [];

    $s = _oxware_api($params, 'GET', "/provision/$vm_id/status");
    if (!empty($s['error'])) return [];

    return [
        'cpu'    => $s['cpu_percent'] ?? 0,
        'memory' => $s['mem_percent'] ?? 0,
        'hdd'    => $s['disk_used_gb'] ?? 0,
    ];
}
