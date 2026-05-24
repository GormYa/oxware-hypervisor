<?php

namespace App\System\Module;

use App\System\Model\ModuleLogModel;
use App\System\Model\UserProductModel;
use App\System\Vendor\beLanguage;
use App\System\Vendor\Basic\beCookie;

/**
 * OXware Hypervisor - DiyoCP Server Module v2.0.0
 *
 * Kurulum: modules/servers/oxware/ dizinine kopyalayin
 *
 * DiyoCP Admin > Sunucular > Yeni Sunucu:
 *   Tip   : OXware Hypervisor
 *   URL   : https://oxware.example.com
 *   Sifre : oxw_... (OXware API anahtari)
 */

class oxware
{
    public $options = ['isneedserver' => true];

    public $pages = [
        '/' => [
            'showmenu' => true,
            'name'     => 'Sunucu Yonetimi',
            'icon'     => '<i class="ri-server-line"></i>',
        ],
    ];

    public function oxware_info()
    {
        return [
            'name'        => 'OXware Hypervisor',
            'description' => 'OXware KVM Hypervisor uzerinden sanal sunucu otomasyonu saglar',
            'version'     => '2.0.0',
            'vercode'     => 20,
            'type'        => 'server',
            'author'      => 'OXware Team',
        ];
    }

    public function oxware_connection_test($params = [])
    {
        $res = $this->_api($params['surl'], $params['spassword'], 'GET', '/api/system/stats');
        if (!$res['status']) {
            return ['status' => false, 'message' => $res['message']];
        }
        return ['status' => true];
    }

    public function oxware_order_config()
    {
        return [];
    }

    public function oxware_product_config($params = [])
    {
        return [
            'vcpus' => [
                'name'        => 'vCPU Sayisi',
                'description' => 'Sanal islemci cekirdek sayisi',
                'type'        => 'integer',
                'default'     => '2',
            ],
            'ram_mb' => [
                'name'        => 'RAM (MB)',
                'description' => 'Bellek miktari MB cinsinden (2048 = 2 GB)',
                'type'        => 'integer',
                'default'     => '2048',
            ],
            'disk_gb' => [
                'name'        => 'Disk (GB)',
                'description' => 'Disk alani GB cinsinden',
                'type'        => 'integer',
                'default'     => '50',
            ],
            'os_template' => [
                'name'        => 'OS Sablonu',
                'description' => 'OXware sablon adi (ornek: ubuntu-22.04, debian-12)',
                'type'        => 'string',
                'default'     => 'ubuntu-22.04',
            ],
            'network' => [
                'name'        => 'Ag',
                'description' => 'Libvirt ag adi (ornek: default, br0)',
                'type'        => 'string',
                'default'     => 'default',
            ],
        ];
    }

    public function oxware_create($params = [])
    {
        $server         = $params['server'];
        $userproduct    = $params['userproduct'];
        $productmodules = $params['productmodules'];

        $vm_name = 'vm-' . $userproduct['upid'] . '-' . substr(md5((string) $userproduct['upid']), 0, 6);

        $body = [
            'name'        => $vm_name,
            'vcpus'       => (int)($productmodules['vcpus']    ?? 2),
            'memory_mb'   => (int)($productmodules['ram_mb']   ?? 2048),
            'disk_gb'     => (int)($productmodules['disk_gb']  ?? 50),
            'os_template' => $productmodules['os_template']     ?? 'ubuntu-22.04',
            'network'     => $productmodules['network']         ?? 'default',
            'auto_start'  => true,
        ];

        $res = $this->_api($server['surl'], $server['spassword'], 'POST', '/api/provision/create', $body);

        if (!$res['status']) {
            ModuleLogModel::beCreateModuleLog(
                $userproduct['upid'], 'oxware',
                'VM Olusturma Hatasi', 'VM olusturulurken hata olustu',
                ['response' => $res]
            );
            return ['status' => false, 'message' => 'VM olusturulamadi: ' . $res['message']];
        }

        $vm_id = $res['data']['vm']['id']  ?? $res['data']['vm_id'] ?? '';
        $ip    = $res['data']['vm']['ip']  ?? $res['data']['ip']    ?? '';

        if (!$vm_id) {
            return ['status' => false, 'message' => 'VM olusturuldu ancak VM ID alinamadi'];
        }

        $updata     = ['vm_id' => $vm_id, 'vm_name' => $vm_name, 'ip' => $ip];
        $updatedata = ['updata' => json_encode($updata, JSON_UNESCAPED_UNICODE)];
        if ($ip) {
            $updatedata['uptag'] = $ip;
        }

        UserProductModel::beUpdate($updatedata)->beWhere('upid', $userproduct['upid'])->beExecute();

        return [
            'status'         => true,
            'message'        => 'VM basariyla olusturuldu',
            'url'            => beGetRoute('client.userproduct.userproduct.show', ['upid' => $userproduct['upid']]),
            'activisioninfo' => "VM ID: {$vm_id}\nSunucu Adi: {$vm_name}\nIP: " . ($ip ?: 'Ataniyor...'),
        ];
    }

    public function oxware_manage($params = [])
    {
        $userproduct = $params['userproduct'];
        beCookie::beCreateCookie('be_upid', $userproduct['upid'], true, true);
        return [
            'status'  => true,
            'message' => 'Yonetim paneline yonlendiriliyorsunuz',
            'url'     => beGetRoute('client.userproduct.userproduct.show', ['upid' => $userproduct['upid']]),
        ];
    }

    public function oxware_extend($params = [])
    {
        return ['status' => true];
    }

    public function oxware_suspend($params = [])
    {
        $updata = json_decode($params['userproduct']['updata'], true);
        $vm_id  = $updata['vm_id'] ?? '';
        if (!$vm_id) {
            return ['status' => false, 'message' => 'VM ID bulunamadi'];
        }
        $res = $this->_api($params['server']['surl'], $params['server']['spassword'], 'POST', "/api/provision/{$vm_id}/suspend");
        if (!$res['status']) {
            return ['status' => false, 'message' => 'Askiya alma basarisiz: ' . $res['message']];
        }
        return ['status' => true, 'message' => 'VM askiya alindi'];
    }

    public function oxware_unsuspend($params = [])
    {
        $updata = json_decode($params['userproduct']['updata'], true);
        $vm_id  = $updata['vm_id'] ?? '';
        if (!$vm_id) {
            return ['status' => false, 'message' => 'VM ID bulunamadi'];
        }
        $res = $this->_api($params['server']['surl'], $params['server']['spassword'], 'POST', "/api/provision/{$vm_id}/unsuspend");
        if (!$res['status']) {
            return ['status' => false, 'message' => 'Aktiflestime basarisiz: ' . $res['message']];
        }
        return ['status' => true, 'message' => 'VM aktiflestirildi'];
    }

    public function oxware_terminate($params = [])
    {
        $updata = json_decode($params['userproduct']['updata'], true);
        $vm_id  = $updata['vm_id'] ?? '';
        if (!$vm_id) {
            return ['status' => true, 'message' => 'VM ID yok, zaten silinmis'];
        }
        $res = $this->_api($params['server']['surl'], $params['server']['spassword'], 'DELETE', "/api/provision/{$vm_id}");
        if (!$res['status']) {
            return ['status' => false, 'message' => 'VM silinemedi: ' . $res['message']];
        }
        return ['status' => true, 'message' => 'VM basariyla silindi'];
    }

    public function oxware_clientarea($params = [])
    {
        beLanguage::beReadLang('oxware');
        $server      = $params['server'];
        $userproduct = $params['userproduct'];
        $updata      = json_decode($userproduct['updata'], true);
        $vm_id       = $updata['vm_id'] ?? '';

        if (!$vm_id) {
            return beAjaxError(['message' => 'VM henuz olusturulmamis']);
        }

        $res       = $this->_api($server['surl'], $server['spassword'], 'GET', "/api/provision/{$vm_id}/status");
        $vm_status = 'Bilinmiyor';
        $vm_ip     = $updata['ip'] ?? '';

        if ($res['status']) {
            $vm_status  = $res['data']['status'] ?? 'Bilinmiyor';
            $fetched_ip = $res['data']['ip'] ?? '';
            if ($fetched_ip && !$vm_ip) {
                $vm_ip        = $fetched_ip;
                $updata['ip'] = $vm_ip;
                UserProductModel::beUpdate([
                    'updata' => json_encode($updata, JSON_UNESCAPED_UNICODE),
                    'uptag'  => $vm_ip,
                ])->beWhere('upid', $userproduct['upid'])->beExecute();
            }
        }

        $vminfo = [
            'vm_id'     => $vm_id,
            'vm_name'   => $updata['vm_name'] ?? $vm_id,
            'ip'        => $vm_ip ?: 'Ataniyor...',
            'status'    => $vm_status,
            'panel_url' => rtrim($server['surl'], '/'),
        ];

        return [
            'status'  => true,
            'title'   => 'VM Yonetimi',
            'content' => beGetView('modules.oxware.server', [
                'vm'          => $vminfo,
                'userproduct' => $userproduct,
            ]),
        ];
    }

    public function oxware_restart($params = [])
    {
        beLanguage::beReadLang('oxware');
        $updata = json_decode($params['userproduct']['updata'], true);
        $vm_id  = $updata['vm_id'] ?? '';
        if (!$vm_id) {
            return beAjaxError(['message' => 'VM ID bulunamadi']);
        }
        $res = $this->_api($params['server']['surl'], $params['server']['spassword'], 'POST', "/api/vms/{$vm_id}/reboot");
        if (!$res['status']) {
            return beAjaxError(['message' => 'Yeniden baslatma basarisiz: ' . $res['message']]);
        }
        return beAjaxSuccess(['message' => 'VM yeniden baslatiliyor']);
    }

    public function oxware_start($params = [])
    {
        beLanguage::beReadLang('oxware');
        $updata = json_decode($params['userproduct']['updata'], true);
        $vm_id  = $updata['vm_id'] ?? '';
        if (!$vm_id) {
            return beAjaxError(['message' => 'VM ID bulunamadi']);
        }
        $res = $this->_api($params['server']['surl'], $params['server']['spassword'], 'POST', "/api/vms/{$vm_id}/start");
        if (!$res['status']) {
            return beAjaxError(['message' => 'Baslatma basarisiz: ' . $res['message']]);
        }
        return beAjaxSuccess(['message' => 'VM baslatiliyor']);
    }

    public function oxware_stop($params = [])
    {
        beLanguage::beReadLang('oxware');
        $updata = json_decode($params['userproduct']['updata'], true);
        $vm_id  = $updata['vm_id'] ?? '';
        if (!$vm_id) {
            return beAjaxError(['message' => 'VM ID bulunamadi']);
        }
        $res = $this->_api($params['server']['surl'], $params['server']['spassword'], 'POST', "/api/vms/{$vm_id}/stop");
        if (!$res['status']) {
            return beAjaxError(['message' => 'Durdurma basarisiz: ' . $res['message']]);
        }
        return beAjaxSuccess(['message' => 'VM durduruluyor']);
    }

    public function oxware_changepackage($params = [])
    {
        $server         = $params['server'];
        $userproduct    = $params['userproduct'];
        $productmodules = $params['productmodules'];
        $updata         = json_decode($userproduct['updata'], true);
        $vm_id          = $updata['vm_id'] ?? '';

        if (!$vm_id) {
            return ['status' => false, 'message' => 'VM ID bulunamadi'];
        }

        $body = [
            'vcpus'     => (int)($productmodules['vcpus']   ?? 2),
            'memory_mb' => (int)($productmodules['ram_mb']  ?? 2048),
            'disk_gb'   => (int)($productmodules['disk_gb'] ?? 50),
        ];

        $res = $this->_api($server['surl'], $server['spassword'], 'PUT', "/api/provision/{$vm_id}/resize", $body);
        if (!$res['status']) {
            return ['status' => false, 'message' => 'Resize basarisiz: ' . $res['message']];
        }
        return ['status' => true, 'message' => 'VM basariyla yeniden boyutlandirildi'];
    }

    // ---- Dahili: OXware REST API ----

    private function _api(string $base_url, string $api_key, string $method, string $endpoint, array $body = null): array
    {
        $base_url = rtrim($base_url, '/');
        if (!preg_match('#^https?://#i', $base_url)) {
            $base_url = 'https://' . $base_url;
        }

        $ch = curl_init($base_url . $endpoint);

        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 30,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_CUSTOMREQUEST  => strtoupper($method),
            CURLOPT_HTTPHEADER     => [
                'Accept: application/json',
                'Content-Type: application/json',
                'X-API-Key: ' . trim($api_key),
            ],
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
        ]);

        foreach (['/etc/ssl/certs/ca-certificates.crt', '/etc/pki/tls/certs/ca-bundle.crt'] as $ca) {
            if (file_exists($ca)) {
                curl_setopt($ch, CURLOPT_CAINFO, $ca);
                break;
            }
        }

        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
        }

        $raw      = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlErr  = curl_error($ch);
        curl_close($ch);

        if ($raw === false || $curlErr) {
            return ['status' => false, 'message' => 'Baglanti hatasi: ' . $curlErr];
        }

        $data = json_decode($raw, true);

        if ($httpCode >= 400) {
            return [
                'status'    => false,
                'message'   => $data['error'] ?? $data['message'] ?? "HTTP {$httpCode}",
                'http_code' => $httpCode,
            ];
        }

        return ['status' => true, 'data' => $data ?? [], 'http_code' => $httpCode];
    }
}
