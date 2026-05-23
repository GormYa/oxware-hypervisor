<?php
/**
 * OXware Hypervisor — DiyoCP Server Module
 * Versiyon: 1.0.0
 *
 * Kurulum:
 *   Bu klasörü DiyoCP'nin modules/servers/ dizinine kopyalayın:
 *     modules/servers/oxware/
 *   Ardından: DiyoCP Admin → Sunucular → Yeni Sunucu → Tip: OXware
 *
 * Sunucu ayarları (DiyoCP Admin paneli):
 *   hostname  : OXware API URL (ör: https://oxware.example.com)
 *   password  : OXware API anahtarı (oxw_... ile başlar)
 *
 * Paket ayarları (configoptions):
 *   cpu, ram_mb, disk_gb, os_template, network
 */

class Servers_Oxware
{
    // ── Metadata ──────────────────────────────────────────────────────────────

    public static $ModuleVersion  = '1.0.0';
    public static $ModuleName     = 'OXware Hypervisor';
    public static $ModuleAuthor   = 'OXware Team';

    public static function MetaData()
    {
        return [
            'DisplayName' => 'OXware Hypervisor',
            'APIVersion'  => '1.1',
            'RequiresServer' => true,
        ];
    }

    public static function getConfig()
    {
        return [
            'name'     => 'OXware Hypervisor',
            'version'  => self::$ModuleVersion,
            'settings' => [
                'cpu' => [
                    'type'        => 'text',
                    'label'       => 'CPU (vCPU)',
                    'value'       => '2',
                    'description' => 'Sanal CPU sayısı',
                ],
                'ram_mb' => [
                    'type'        => 'text',
                    'label'       => 'RAM (MB)',
                    'value'       => '2048',
                    'description' => 'Bellek MB cinsinden (2048 = 2 GB)',
                ],
                'disk_gb' => [
                    'type'        => 'text',
                    'label'       => 'Disk (GB)',
                    'value'       => '50',
                    'description' => 'Disk alanı GB cinsinden',
                ],
                'os_template' => [
                    'type'        => 'text',
                    'label'       => 'OS Template',
                    'value'       => 'ubuntu-22.04',
                    'description' => 'OXware template ID (ör: ubuntu-22.04, debian-12)',
                ],
                'network' => [
                    'type'        => 'text',
                    'label'       => 'Network',
                    'value'       => 'default',
                    'description' => 'Libvirt ağ adı (ör: default, br0)',
                ],
            ],
        ];
    }

    // ── Yardımcı: OXware REST API ─────────────────────────────────────────────

    private static function api($server, $method, $endpoint, $body = null)
    {
        $base = rtrim(
            $server['serverhostname'] ?? $server['ip_address'] ?? $server['hostname'] ?? $server['host'] ?? '',
            '/'
        );
        $key = trim($server['serverpassword'] ?? $server['api_key'] ?? $server['password'] ?? '');

        if (!$base) {
            return ['error' => 'Sunucu adresi tanımlı değil'];
        }

        // https eksikse ekle
        if (!preg_match('#^https?://#i', $base)) {
            $base = 'https://' . $base;
        }

        // SSL: sistem CA bundle
        $ca_path = '';
        foreach (['/etc/ssl/certs/ca-certificates.crt', '/etc/pki/tls/certs/ca-bundle.crt'] as $f) {
            if (file_exists($f)) { $ca_path = $f; break; }
        }

        $ch = curl_init($base . '/api' . $endpoint);
        $curl_opts = [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 30,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_CUSTOMREQUEST  => strtoupper($method),
            CURLOPT_HTTPHEADER     => [
                'Content-Type: application/json',
                'Accept: application/json',
                'X-API-Key: ' . $key,
            ],
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
        ];

        if ($ca_path) {
            $curl_opts[CURLOPT_CAINFO] = $ca_path;
        }

        // Self-signed geliştirme ortamı: sunucu ayarından kontrol et
        if (!empty($server['serversecure']) && $server['serversecure'] == 0) {
            $curl_opts[CURLOPT_SSL_VERIFYPEER] = false;
            $curl_opts[CURLOPT_SSL_VERIFYHOST] = 0;
        }

        curl_setopt_array($ch, $curl_opts);

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
            return ['error' => $data['error'] ?? "HTTP $http_code"];
        }

        return $data ?? [];
    }

    // ── UUID doğrulama ────────────────────────────────────────────────────────

    private static function validateVmId($vm_id)
    {
        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $vm_id)) {
            throw new Exception('Geçersiz VM ID formatı: ' . htmlspecialchars($vm_id));
        }
    }

    // ── create ────────────────────────────────────────────────────────────────

    public static function create($params)
    {
        $server  = $params;
        $package = $params['configoptions'] ?? $params;
        $account = $params;

        $client_id = $account['clientid'] ?? $account['userid'] ?? rand(10000, 99999);
        $domain    = preg_replace('/[^a-z0-9\-]/', '', strtolower($account['domain'] ?? 'vm'));
        $name      = 'vm-' . $client_id . '-' . ($domain ?: 'vm');

        $body = [
            'name'        => $name,
            'cpu'         => (int)($package['cpu'] ?? 2),
            'ram_mb'      => (int)($package['ram_mb'] ?? 2048),
            'disk_gb'     => (int)($package['disk_gb'] ?? 50),
            'os_template' => $package['os_template'] ?? 'ubuntu-22.04',
            'network'     => $package['network'] ?? 'default',
            'auto_start'  => true,
        ];

        $result = self::api($server, 'POST', '/provision/create', $body);

        if (!empty($result['error'])) {
            throw new Exception($result['error']);
        }

        $vm_id = $result['vm']['id'] ?? $result['vm_id'] ?? '';
        $ip    = $result['vm']['ip']
              ?? ($result['vm']['networks'][0]['ip'] ?? '')
              ?: '';

        if (!$vm_id) {
            throw new Exception('VM oluşturuldu ancak VM ID alınamadı');
        }

        return [
            'username' => $vm_id,
            'password' => '',
            'ip'       => $ip,
        ];
    }

    // ── suspend ───────────────────────────────────────────────────────────────

    public static function suspend($params)
    {
        $vm_id = $params['username'] ?? '';
        if (!$vm_id) throw new Exception('VM ID bulunamadı (username alanı boş)');
        self::validateVmId($vm_id);

        $result = self::api($params, 'POST', "/provision/$vm_id/suspend");
        if (!empty($result['error'])) throw new Exception($result['error']);
        return 'success';
    }

    // ── unsuspend ─────────────────────────────────────────────────────────────

    public static function unsuspend($params)
    {
        $vm_id = $params['username'] ?? '';
        if (!$vm_id) throw new Exception('VM ID bulunamadı (username alanı boş)');
        self::validateVmId($vm_id);

        $result = self::api($params, 'POST', "/provision/$vm_id/unsuspend");
        if (!empty($result['error'])) throw new Exception($result['error']);
        return 'success';
    }

    // ── terminate ─────────────────────────────────────────────────────────────

    public static function terminate($params)
    {
        $vm_id = $params['username'] ?? '';
        if (!$vm_id) return 'success'; // Zaten yok, sorun değil

        // Geçersiz UUID ise sessizce geç
        if (!preg_match('/^[0-9a-f\-]{36}$/i', $vm_id)) {
            return 'success';
        }

        $result = self::api($params, 'DELETE', "/provision/$vm_id");
        if (!empty($result['error'])) throw new Exception($result['error']);
        return 'success';
    }

    // ── resize / upgrade ──────────────────────────────────────────────────────

    public static function changePackage($params)
    {
        $vm_id   = $params['username'] ?? '';
        if (!$vm_id) throw new Exception('VM ID bulunamadı');
        self::validateVmId($vm_id);

        $package = $params['configoptions'] ?? $params;
        $body = [
            'cpu'     => (int)($package['cpu'] ?? 2),
            'ram_mb'  => (int)($package['ram_mb'] ?? 2048),
            'disk_gb' => (int)($package['disk_gb'] ?? 50),
        ];

        $result = self::api($params, 'PUT', "/provision/$vm_id/resize", $body);
        if (!empty($result['error'])) throw new Exception($result['error']);
        return 'success';
    }

    // ── status / info ─────────────────────────────────────────────────────────

    public static function getDetails($params)
    {
        $vm_id = $params['username'] ?? '';
        if (!$vm_id) return [];

        $s = self::api($params, 'GET', "/provision/$vm_id/status");
        if (!empty($s['error'])) return [];

        return [
            'status'     => $s['status']       ?? 'unknown',
            'ip'         => $s['ip']           ?? '',
            'cpu_usage'  => $s['cpu_percent']  ?? 0,
            'ram_usage'  => $s['mem_percent']  ?? 0,
            'disk_used'  => $s['disk_used_gb'] ?? 0,
        ];
    }

    // DiyoCP compat alias
    public static function status($params)
    {
        return self::getDetails($params);
    }

    // ── testConnection ────────────────────────────────────────────────────────

    public static function testConnection($params)
    {
        $result = self::api($params, 'GET', '/system/stats');
        if (!empty($result['error'])) {
            throw new Exception($result['error']);
        }
        return 'Connection successful';
    }
}
