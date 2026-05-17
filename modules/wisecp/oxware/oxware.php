<?php
/**
 * OXware Hypervisor — WiseCP Server Module
 * Versiyon: 1.0.0
 *
 * Kurulum:
 *   Bu klasörü WiseCP'nin modules/server/ dizinine kopyalayın:
 *     modules/server/oxware/
 *   Ardından: WiseCP Admin → Sunucular → Yeni Sunucu → Tip: OXware
 *
 * Sunucu ayarları (WiseCP Admin paneli):
 *   ip_address / hostname : OXware API URL (ör: https://oxware.example.com)
 *   password / api_key    : OXware API anahtarı (oxw_... ile başlar)
 *
 * Paket ayarları:
 *   cpu, ram_mb, disk_gb, os_template, network
 */

class Server_oxware
{
    // ── Metadata ──────────────────────────────────────────────────────────────

    public static function getConfig()
    {
        return [
            'name'     => 'OXware Hypervisor',
            'version'  => '1.0.0',
            'settings' => [
                'cpu' => [
                    'type'    => 'text',
                    'label'   => 'CPU (vCPU)',
                    'value'   => '2',
                    'description' => 'Sanal CPU sayısı',
                ],
                'ram_mb' => [
                    'type'    => 'text',
                    'label'   => 'RAM (MB)',
                    'value'   => '2048',
                    'description' => 'Bellek MB cinsinden (2048 = 2 GB)',
                ],
                'disk_gb' => [
                    'type'    => 'text',
                    'label'   => 'Disk (GB)',
                    'value'   => '50',
                    'description' => 'Disk alanı GB cinsinden',
                ],
                'os_template' => [
                    'type'    => 'text',
                    'label'   => 'OS Template',
                    'value'   => 'ubuntu-22.04',
                    'description' => 'OXware template ID',
                ],
                'network' => [
                    'type'    => 'text',
                    'label'   => 'Network',
                    'value'   => 'default',
                    'description' => 'Libvirt ağ adı',
                ],
            ],
        ];
    }

    // ── Yardımcı: OXware REST API ─────────────────────────────────────────────

    private static function api($server, $method, $endpoint, $body = null)
    {
        $base = rtrim(
            $server['ip_address'] ?? $server['hostname'] ?? $server['host'] ?? '',
            '/'
        );
        $key = trim($server['api_key'] ?? $server['password'] ?? '');

        if (!$base) {
            return ['error' => 'Sunucu adresi tanımlı değil'];
        }

        $ch = curl_init($base . '/api' . $endpoint);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 30,
            CURLOPT_CUSTOMREQUEST  => strtoupper($method),
            CURLOPT_HTTPHEADER     => [
                'Content-Type: application/json',
                'X-API-Key: ' . $key,
            ],
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
            return ['error' => $data['error'] ?? "HTTP $http_code"];
        }

        return $data ?? [];
    }

    // ── create ────────────────────────────────────────────────────────────────

    public static function create($package, $account, $server)
    {
        $name = 'vm-' . ($account['id'] ?? rand(10000, 99999))
              . '-' . preg_replace('/[^a-z0-9\-]/', '', strtolower($account['domain'] ?? 'vm'));

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
            throw new Exception('VM ID alınamadı');
        }

        // WiseCP: dönen değerler servis kaydına yazılır
        return [
            'username' => $vm_id,
            'password' => '',
            'ip'       => $ip,
            'ns1'      => '',
            'ns2'      => '',
        ];
    }

    // ── suspend ───────────────────────────────────────────────────────────────

    public static function suspend($package, $account, $server)
    {
        $vm_id = $account['username'] ?? '';
        if (!$vm_id) throw new Exception('VM ID bulunamadı');

        $result = self::api($server, 'POST', "/provision/$vm_id/suspend");
        if (!empty($result['error'])) throw new Exception($result['error']);
        return true;
    }

    // ── unsuspend ─────────────────────────────────────────────────────────────

    public static function unsuspend($package, $account, $server)
    {
        $vm_id = $account['username'] ?? '';
        if (!$vm_id) throw new Exception('VM ID bulunamadı');

        $result = self::api($server, 'POST', "/provision/$vm_id/unsuspend");
        if (!empty($result['error'])) throw new Exception($result['error']);
        return true;
    }

    // ── terminate ─────────────────────────────────────────────────────────────

    public static function terminate($package, $account, $server)
    {
        $vm_id = $account['username'] ?? '';
        if (!$vm_id) return true; // Zaten yok

        $result = self::api($server, 'DELETE', "/provision/$vm_id");
        if (!empty($result['error'])) throw new Exception($result['error']);
        return true;
    }

    // ── resize ────────────────────────────────────────────────────────────────

    public static function resize($package, $account, $server)
    {
        $vm_id = $account['username'] ?? '';
        if (!$vm_id) throw new Exception('VM ID bulunamadı');

        $body = [
            'cpu'     => (int)($package['cpu'] ?? 2),
            'ram_mb'  => (int)($package['ram_mb'] ?? 2048),
            'disk_gb' => (int)($package['disk_gb'] ?? 50),
        ];

        $result = self::api($server, 'PUT', "/provision/$vm_id/resize", $body);
        if (!empty($result['error'])) throw new Exception($result['error']);
        return true;
    }

    // ── info ──────────────────────────────────────────────────────────────────

    public static function info($package, $account, $server)
    {
        $vm_id = $account['username'] ?? '';
        if (!$vm_id) return [];

        $s = self::api($server, 'GET', "/provision/$vm_id/status");
        if (!empty($s['error'])) return [];

        return [
            'status'    => $s['status']      ?? 'unknown',
            'ip'        => $s['ip']          ?? '',
            'cpu_usage' => $s['cpu_percent'] ?? 0,
            'ram_usage' => $s['mem_percent'] ?? 0,
            'disk_used' => $s['disk_used_gb'] ?? 0,
        ];
    }

    // ── testConnection ────────────────────────────────────────────────────────

    public static function testConnection($server)
    {
        $result = self::api($server, 'GET', '/system/stats');
        if (!empty($result['error'])) {
            throw new Exception($result['error']);
        }
        return true;
    }
}
