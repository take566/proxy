# 設計: Chocolatey Squid (Windows) の設定管理と HTTPS キャッシュ

Issue: https://github.com/take566/proxy/issues/1

## 1. 前提・現状

| 項目 | 値 |
|---|---|
| パッケージ | `choco install squid` → Diladele Squid for Windows 4.14 (msi) |
| 配置先 | `D:\Squid`（Cygwin ルート。`/etc/squid/...` = `D:\Squid\etc\squid\...`） |
| サービス | `squidsrv`（`Diladele.Squid.Service.exe` が `squid.exe` をラップ） |
| ビルド | `--with-openssl --enable-ssl-crtd` あり → SSL Bump 可 |
| 証明書ヘルパー | `D:\Squid\lib\squid\security_file_certgen.exe`（Cygwin パス `/lib/squid/security_file_certgen`） |
| 待受 | `3128` |

## 2. 方針

1. **正本はリポジトリ**。`squid/squid.conf` を編集し、`scripts/deploy-config.ps1` で
   `D:\Squid\etc\squid\squid.conf` にコピー → `squid -k parse` で構文検証 → サービス再起動。
   直接 `D:\Squid` 側を編集しない。
2. **HTTPS キャッシュは SSL Bump（フル bump）**。
   - `http_port 3128 ssl-bump generate-host-certificates=on tls-cert=... tls-key=...`
   - `sslcrtd_program /lib/squid/security_file_certgen -s /var/cache/squid_ssldb -M 4MB`
   - `acl step1 at_step SslBump1` → `ssl_bump peek step1` → `ssl_bump splice nobump` → `ssl_bump bump all`
   - 証明書ピンニング等で壊れるドメインは `squid/nobump.txt`（`ssl::server_name`）で splice（復号しない）。
3. **CA はローカル生成、秘密鍵は commit しない**。
   - `scripts/gen-ca.ps1` が `D:\Squid\etc\squid\ssl\squid-ca.{key,pem,crt}` を生成し、
     `Cert:\LocalMachine\Root` にインポート（要管理者）。
   - リポジトリの `.gitignore` で `*.key` / `*.pem` を除外。
4. **ディスクキャッシュを有効化**。`cache_dir ufs /var/cache/squid 4096 16 256`（Cygwin では aufs/rock より ufs が安全）。
5. **既存 Docker 構成は `docker/` に温存**（Linux 用。今回のスコープ外）。

## 3. リポジトリ構成

```
proxy/
├─ README.md                # 使い方（インストール → CA → 配備 → 検証）
├─ docs/DESIGN.md           # 本書
├─ squid/
│  ├─ squid.conf            # 正本（Windows / Diladele 4.14 向け）
│  └─ nobump.txt            # splice 対象ドメイン（ssl::server_name）
├─ scripts/
│  ├─ install.ps1           # choco install → gen-ca → init-storage → deploy-config
│  ├─ gen-ca.ps1            # CA 生成 + Windows 信頼ルート登録
│  ├─ update-cacert.ps1     # 上流検証用 CA バンドル (Mozilla) 取得
│  ├─ trust-ca-firefox.ps1  # Firefox ポリシー ImportEnterpriseRoots=1
│  ├─ run-elevated.ps1      # 非管理者シェルから UAC 昇格して実行 (出力はログ経由)
│  ├─ export-ca.ps1         # 他端末向け配布パッケージ dist/squid-ca.zip を生成 (秘密鍵は含まない)
│  ├─ init-storage.ps1      # ssl_db 初期化 (security_file_certgen -c) と cache_dir 初期化 (squid -z)
│  ├─ deploy-config.ps1     # conf/nobump 配備 → parse → サービス再起動
│  ├─ test-cache.ps1        # HTTP/HTTPS を 2 回取得し access.log の TCP_HIT / X-Cache を確認
│  ├─ find-bump-errors.ps1  # sslbump.log を集計し nobump 候補 (ClientAbort / Errors) を表示
│  └─ add-nobump.ps1        # nobump.txt に追加 (正規化・重複排除) → -Deploy で配備
├─ client/                  # 配布パッケージに同梱するクライアント側スクリプト
│  ├─ install-ca.ps1        # Windows: LocalMachine\Root 登録 + Firefox ポリシー
│  └─ install-ca.sh         # macOS (security) / Debian (update-ca-certificates) / RHEL (update-ca-trust) / Arch (p11-kit)
├─ dist/                    # export-ca.ps1 の出力 (.gitignore)
└─ docker/                  # 旧 Linux (Ubuntu) 構成
```

## 4. squid.conf の要点

| 設定 | 値 | 理由 |
|---|---|---|
| `http_port` | `3128 ssl-bump generate-host-certificates=on dynamic_cert_mem_cache_size=16MB tls-cert=/etc/squid/ssl/squid-ca.pem tls-key=/etc/squid/ssl/squid-ca.key` | HTTPS 復号 |
| `sslcrtd_program` | `/lib/squid/security_file_certgen -s /var/cache/squid_ssldb -M 16MB` | 動的証明書 |
| `ssl_bump` | `peek step1` → `splice nobump` → `bump all` | SNI で判定してから bump |
| `tls_outgoing_options` | `cafile=/etc/squid/ssl/cacert.pem` | Cygwin 版 Squid は OS の証明書ストアを見ないため Mozilla バンドルを明示（`update-cacert.ps1` で取得） |
| `sslproxy_cert_error` | 指定しない（既定 deny） | 上流の不正証明書は通さない |
| `cache_dir` | `ufs /var/cache/squid 4096 16 256` | Cygwin で安定 |
| `cache_mem` / `maximum_object_size` | `256 MB` / `512 MB` | 大きめのバイナリもキャッシュ |
| `refresh_pattern` | 既定 + 静的アセット（画像/JS/CSS/アーカイブ）を `10080 90% 43200` | ヒット率向上 |
| `dns_nameservers` | Diladele 既定 (8.8.8.8 等) を踏襲 | Windows のリゾルバを Cygwin から使えない場合の保険 |
| `logformat sslbump` / `access_log sslbump.log` | `%ssl::bump_mode %ssl::>sni %err_code/%err_detail` を CONNECT / https のみ記録 | cache.log の TLS エラーにはドメインが出ないため。`find-bump-errors.ps1` の入力 |

## 5. セキュリティ上の注意

- SSL Bump は中間者復号。**このホスト（と CA を信頼させた端末）専用**。`localnet` の allow 範囲を広げすぎない。
- CA 秘密鍵は `D:\Squid\etc\squid\ssl\squid-ca.key` のみに置き、リポジトリ・共有には出さない。
- Windows の `.ps1` は **UTF-8 BOM 付き**で保存する（PowerShell 5.1 が BOM 無しを Shift-JIS と解釈し、日本語コメント末尾が改行を飲み込む）。`.gitattributes` で `*.ps1` は CRLF。
- `curl.exe`（Schannel）は動的証明書に CRL 配布点が無いため失効確認で失敗する → 検証時は `--ssl-no-revoke`。ブラウザは影響なし。
- Firefox は OS ストアを見ないため `scripts/trust-ca-firefox.ps1` でポリシー `HKLM\SOFTWARE\Policies\Mozilla\Firefox\Certificates\ImportEnterpriseRoots=1` を設定（`security.enterprise_roots.enabled` 相当）。
- 証明書ピンニングを行うアプリ（Windows Update, 一部の SaaS クライアント、決済系）は `nobump.txt` に追加。

## 6. 検証手順（`scripts/test-cache.ps1`）

1. `curl.exe --ssl-no-revoke -x http://127.0.0.1:3128 -sS -o NUL -D - https://example.com/` を 2 回実行
2. 2 回目のレスポンスヘッダ `X-Cache: HIT from ...` を確認
3. `D:\Squid\var\log\squid\access.log` 末尾に `TCP_HIT`/`TCP_MEM_HIT` があることを確認

## 7. タスク分解

| # | タスク | 成果物 |
|---|---|---|
| 1 | 設計・README | `docs/DESIGN.md`, `README.md` |
| 2 | リポジトリ再編 | `docker/` へ移動、`.gitignore` |
| 3 | Windows 向け squid.conf | `squid/squid.conf`, `squid/nobump.txt` |
| 4 | CA 生成 / CA バンドル取得 | `scripts/gen-ca.ps1`, `scripts/update-cacert.ps1` |
| 5 | ストレージ初期化 | `scripts/init-storage.ps1` |
| 6 | インストール / 配備 | `scripts/install.ps1`, `scripts/deploy-config.ps1` |
| 7 | 検証 | `scripts/test-cache.ps1` |
| 8 | 実機で HTTPS HIT を確認 → PR | PR |

## 8. 実機検証結果 (2026-09-12)

```
==> http://example.com/
  #1: HTTP/1.1 200 OK | X-Cache: MISS from squid-win
  #2: HTTP/1.1 200 OK | X-Cache: HIT from squid-win
==> https://example.com/
  #1: HTTP/1.1 200 OK | X-Cache: MISS from squid-win
  #2: HTTP/1.1 200 OK | X-Cache: HIT from squid-win
==> https://www.gnu.org/graphics/heckert_gnu.transp.small.png
  #1: HTTP/1.1 200 OK | X-Cache: MISS from squid-win
  #2: HTTP/1.1 200 OK | X-Cache: HIT from squid-win
access.log: TCP_MEM_HIT/200 34320 GET https://www.gnu.org/graphics/heckert_gnu.transp.small.png - HIER_NONE/-
```
