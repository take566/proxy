# proxy

Windows 上の Squid (Chocolatey / Diladele 4.14) の設定をこのリポジトリで管理し、SSL Bump で HTTPS もキャッシュする。
設計は [docs/DESIGN.md](docs/DESIGN.md)。

## 構成

| パス | 内容 |
|---|---|
| `squid/squid.conf` | 設定の正本 (`D:\Squid\etc\squid\squid.conf` へ配備) |
| `squid/nobump.txt` | SSL Bump しない (splice する) ドメイン |
| `scripts/*.ps1` | セットアップ / 配備 / 検証 (要 管理者 PowerShell) |
| `docker/` | 旧 Linux (Ubuntu) 用構成 |

## 初回セットアップ (管理者 PowerShell)

```powershell
.\scripts\install.ps1
```

内部で以下を順に実行する。個別に実行してもよい。

```powershell
choco install squid -y             # D:\Squid にインストール、サービス squidsrv
.\scripts\gen-ca.ps1               # CA 生成 (D:\Squid\etc\squid\ssl\) + 信頼ルート登録
.\scripts\update-cacert.ps1        # 上流検証用 CA バンドル (Mozilla) を取得
.\scripts\deploy-config.ps1 -NoRestart
.\scripts\init-storage.ps1         # ssl_db / cache_dir 初期化
Restart-Service squidsrv
.\scripts\test-cache.ps1           # HTTP/HTTPS を 2 回取得して HIT を確認
```

非管理者のシェルからは `run-elevated.ps1` 経由で実行できる (UAC ダイアログが出る。出力はログファイル経由で表示)。

```powershell
.\scripts\run-elevated.ps1 deploy-config.ps1
.\scripts\run-elevated.ps1 init-storage.ps1 -Force
```

## 設定変更の流れ

1. `squid/squid.conf` または `squid/nobump.txt` を編集
2. `.\scripts\deploy-config.ps1` (バックアップ → コピー → `squid -k parse` → サービス再起動)
3. `.\scripts\test-cache.ps1`

## クライアント設定

- プロキシ: `http://<このホスト>:3128`
- HTTPS を復号するため、`D:\Squid\etc\squid\ssl\squid-ca.crt` を各クライアントの信頼されたルート証明機関に登録する
  (このホストは `gen-ca.ps1` が登録済み)。
- Firefox は OS ストアを見ないため `scripts/trust-ca-firefox.ps1` でポリシー `ImportEnterpriseRoots=1` を設定する
  (`gen-ca.ps1` が Firefox 検出時に自動実行。Firefox 再起動後 `about:policies` で確認)。
- 証明書ピンニングで壊れるサービスは `squid/nobump.txt` に追加する。

## 注意

- `*.key` / `*.pem` / `*.crt` は `.gitignore` 済み。**CA 秘密鍵は commit しない**。
- CA を再生成した場合は `.\scripts\init-storage.ps1 -Force` で ssl_db も作り直す。
- CA バンドルは 30 日以上古いと `update-cacert.ps1` が再取得する。更新後は `deploy-config.ps1` で再起動。
- `curl.exe` で検証する際は `--ssl-no-revoke` が必要（動的証明書に CRL が無いため）。ブラウザは影響なし。
- `.ps1` は UTF-8 BOM 付きで保存すること（PowerShell 5.1 対策）。
- ログ: `D:\Squid\var\log\squid\{access,cache}.log`
