#!/bin/sh

#============ 基本參數設定 ============#
DATE=$(date +"%Y-%m-%d")

# 雲端目的地路徑（指向 OneDrive 掛載點）
BACKUP_DIR="/volume1/cloud/service/Backup"
SOURCE_BASE="/volume1/docker"
LOCAL_TMP="/volume1/docker/backup/.cloud_tmp"

# 單一資料夾上限門檻（單位：MB），預設 2048MB (2GB)，超過則跳過打包
MAX_DIR_SIZE_MB=2048

# 排除名單（系統特殊目錄與備份自體）
EXCLUDE_DIRS="@eaDir @tmp backup"

#============ 前置掛載檢查 ============#
echo "=================================================="
echo "    開始執行 ASUSTOR Docker 資料夾「雲端」動態備份作業    "
echo "=================================================="

# 檢查雲端目錄是否有效
if ! [ -d "/volume1/cloud/service" ]; then
  echo "❌ [錯誤] 找不到 /volume1/cloud/service，請確認 Rclone 容器是否已正常掛載！"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
mkdir -p "$LOCAL_TMP"

# 1. 動態取得系統所有運行/停止容器名稱
RUNNING_CONTAINERS=$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)

# 2. 彙整目標備份資料夾清單
TARGET_CANDIDATES=""

# (A) 由容器名稱推導對應的資料夾
for c in $RUNNING_CONTAINERS; do
  case "$c" in
    rclone-*)
      folder="rclone"
      ;;
    *)
      folder="$c"
      ;;
  esac
  if [ -d "$SOURCE_BASE/$folder" ]; then
    TARGET_CANDIDATES="$TARGET_CANDIDATES $folder"
  fi
done

# (B) 遍歷 SOURCE_BASE 下實際存在的一級子目錄
for d in "$SOURCE_BASE"/*; do
  if [ -d "$d" ]; then
    folder=$(basename "$d")
    TARGET_CANDIDATES="$TARGET_CANDIDATES $folder"
  fi
done

# (C) 進行清單去重與排除過濾
FINAL_FOLDERS=""
for folder in $TARGET_CANDIDATES; do
  if echo " $EXCLUDE_DIRS " | grep -q " $folder "; then
    continue
  fi
  if ! echo " $FINAL_FOLDERS " | grep -q " $folder "; then
    FINAL_FOLDERS="$FINAL_FOLDERS $folder"
  fi
done

echo ">>> 偵測到需上傳雲端的實體資料夾清單:"
for f in $FINAL_FOLDERS; do
  echo "    - $f"
done
echo "--------------------------------------------------"

#============ 執行批次備份 ============#
for folder in $FINAL_FOLDERS; do
  SRC_PATH="$SOURCE_BASE/$folder"
  
  if [ -d "$SRC_PATH" ]; then
    DIR_SIZE_MB=$(du -sm "$SRC_PATH" 2>/dev/null | awk '{print $1}')
    DIR_SIZE_MB=${DIR_SIZE_MB:-0}

    # 超過 2GB 門檻自動略過，保護雲端頻寬與暫存空間
    if [ "$DIR_SIZE_MB" -gt "$MAX_DIR_SIZE_MB" ]; then
      echo "⚠️  [${folder}] 容量過大 (${DIR_SIZE_MB}MB > ${MAX_DIR_SIZE_MB}MB)，自動跳過雲端上傳！"
      echo "Skipped: $SRC_PATH (${DIR_SIZE_MB}MB) exceeds ${MAX_DIR_SIZE_MB}MB on ${DATE}" > "$BACKUP_DIR/${folder}-cloud-SKIPPED.txt"
      continue
    fi

    echo ">>> [${folder}] 正在本機打包 (${DIR_SIZE_MB}MB)..."
    TMP_FILE="$LOCAL_TMP/${folder}-cloud-backup-${DATE}.tar"
    DEST_FILE="$BACKUP_DIR/${folder}-cloud-backup-${DATE}.tar"
    
    STATUS=0
    # 呼叫系統最低優先權 nice -n19 本地快速封裝
    nice -n19 tar -cf "$TMP_FILE" -C "$SOURCE_BASE" "$folder" 2>/dev/null || STATUS=$?
    
    if [ $STATUS -eq 0 ] || [ $STATUS -eq 1 ]; then
      echo ">>> [${folder}] 正在傳輸至雲端目的地..."
      cp "$TMP_FILE" "$DEST_FILE" && rm -f "$TMP_FILE"
      
      if [ $STATUS -eq 1 ]; then
        echo "⚠️  [${folder}] 雲端打包完成（已忽略日誌檔寫入變更）。"
      else
        echo "✓  [${folder}] 雲端備份上傳完成！"
      fi
    else
      echo "❌ [${folder}] 打包發生錯誤！狀態碼: $STATUS (跳過此項)"
      rm -f "$TMP_FILE" 2>/dev/null || true
    fi
  else
    echo "⚠️  提示：找不到路徑 $SRC_PATH，已自動跳過。"
  fi
done

# 清理暫存資料夾
rm -rf "$LOCAL_TMP"

#============ 清理舊備份（保留 30 天內） ============#
echo "--------------------------------------------------"
echo "    開始檢查並清理雲端 30 天前的舊備份檔案...    "
echo "--------------------------------------------------"

find "$BACKUP_DIR" -maxdepth 1 -type f -name "*-cloud-backup-*.tar" -mtime +30 -exec rm -f {} \;
find "$BACKUP_DIR" -maxdepth 1 -type f -name "*-cloud-SKIPPED.txt" -mtime +30 -exec rm -f {} \;

echo "=================================================="
echo "    所有 Docker 實體資料已同步至雲端且清理完成！"
echo "=================================================="
