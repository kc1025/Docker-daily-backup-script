# NAS Docker Auto Backup Scripts

專為 NAS（ASUSTOR / Synology DSM / Linux）設計的高效能 Docker 容器實體目錄動態備份方案。具備**動態偵測現存容器**、**大檔案容量防爆**、**無感背景低優先級打包**及**雲端 FUSE 安全寫入機制**。

---

## 核心特色

- **動態容器偵測**：自動透過 `docker ps -a` 及 `/volume1/docker/` 目錄結構識別所有現存容器，日後新增或刪除容器無需手動維護腳本清單。
- **智慧去重與前綴合併**：自動處理容器名稱與掛載目錄不一致的情況（例如多個 `rclone-*` 實例統一合併備份至 `rclone` 目錄）。
- **容量防護機制（2GB 守門員）**：打包前自動計算目錄容量，若超過預設門檻（2048 MB）自動略過並輸出 `.txt` 記錄，防止下載器（如 Transmission / qBittorrent）的影音大檔塞爆 USB 或雲端空間。
- **無感低負載打包**：採用 `nice -n19` 以最低系統排程優先級執行打包，絕不影響 NAS 當前運作效能。
- **快取與歷史輪替**：備份檔案保留最近 30 天，過期檔案與標記檔自動清理。
- **雲端寫入安全防護（僅雲端版）**：先於本地暫存區完成封裝後再寫入 Rclone FUSE 掛載點，避免因雲端網路延遲造成 `tar` 指令異常中斷。

---

## 腳本架構與說明

| 腳本名稱 | 適用情境 | 預設儲存目標 | 特殊機制 |
| :--- | :--- | :--- | :--- |
| `docker_backup.sh` | 外接硬碟 / 本地冷備份 | `/share/USB2/Backup/AS6702T` | 極速 `.tar` 直出、排除系統索引檔 |
| `docker_cloud_backup.sh` | 異地雲端備份（OneDrive / pCloud / C2） | `/volume1/cloud/service/Backup` | FUSE 掛載點在線檢驗、本地暫存後推入 |

---

## 目錄預設與參數設定

兩支腳本頂部皆包含核心參數，可依個人環境彈性調整：

```bash
# 預設儲存位置
BACKUP_DIR="..."            # 本地 USB 路徑 或 雲端掛載目錄
SOURCE_BASE="/volume1/docker" # Docker 實體配置檔根目錄

# 容量上限門檻（單位：MB）
MAX_DIR_SIZE_MB=2048        # 預設 2GB，超過則跳過打包並留下日誌

# 系統保留與排除清單
EXCLUDE_DIRS="@eaDir @tmp backup" # 預設略過 NAS 縮圖、快取及備份自體資料夾
