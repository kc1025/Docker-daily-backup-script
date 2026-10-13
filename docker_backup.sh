#!/bin/sh

#============ 基本參數設定 ============#
DATE=$(date +"%Y-%m-%d")
BACKUP_DIR="/share/USB2/Backup/AS6702T"
SOURCE_BASE="/volume1/docker"

# 單一資料夾上限門檻（單位：MB），預設 2048MB (2GB)，超過則跳過打包並紀錄
MAX_DIR_SIZE_MB=2048

# 排除名單（如有特定資料夾不打包，可在引號內以空白隔開）
EXCLUDE_DIRS="@eaDir @tmp backup"

#============ 前置作業 ============#
mkdir -p "$BACKUP_DIR"

echo "=================================================="
echo "    開始執行 ASUSTOR Docker 資料夾動態備份作業    "
echo "=================================================="

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

# (B) 遍歷 SOURCE_BASE 下實際存在的一級子目錄（避免有配置檔但容器未啟動）
for d in "$SOURCE_BASE"/*; do
  if [ -d "$d" ]; then
    folder=$(basename "$d")
    TARGET_CANDIDATES="$TARGET_CANDIDATES $folder"
  fi
done

# (C) 進行清單去重與排除過濾
FINAL_FOLDERS=""
for folder in $TARGET_CANDIDATES; do
  # 檢查是否在排除清單內
  if echo " $EXCLUDE_DIRS " | grep -q " $folder "; then
    continue
  fi
  # 去除重複項
  if ! echo " $FINAL_FOLDERS " | grep -q " $folder "; then
    FINAL_FOLDERS="$FINAL_FOLDERS $folder"
  fi
done

echo ">>> 偵測到需備份的實體資料夾清單:"
for f in $FINAL_FOLDERS; do
  echo "    - $f"
done
echo "--------------------------------------------------"

#============ 執行批次備份 ============#
for folder in $FINAL_FOLDERS; do
  SRC_PATH="$SOURCE_BASE/$folder"
  
  if [ -d "$SRC_PATH" ]; then
    # 檢查資料夾容量大小
    DIR_SIZE_MB=$(du -sm "$SRC_PATH" 2>/dev/null | awk '{print $1}')
    DIR_SIZE_MB=${DIR_SIZE_MB:-0}

    if [ "$DIR_SIZE_MB" -gt "$MAX_DIR_SIZE_MB" ]; then
      echo "⚠️  [${folder}] 容量過大 (${DIR_SIZE_MB}MB > ${MAX_DIR_SIZE_MB}MB)，自動跳過避免塞滿 USB！"
      echo "Skipped: $SRC_PATH (${DIR_SIZE_MB}MB) exceeds ${MAX_DIR_SIZE_MB}MB on ${DATE}" > "$BACKUP_DIR/${folder}-SKIPPED.txt"
      continue
    fi

    echo ">>> [${folder}] 正在打包備份中 (${DIR_SIZE_MB}MB)..."
    BACKUP_FILE="$BACKUP_DIR/${folder}-backup-${DATE}.tar"
    
    STATUS=0
    # 呼叫系統最低優先權 nice -n19，背景無感打包
    nice -n19 tar -cf "$BACKUP_FILE" -C "$SOURCE_BASE" "$folder" 2>/dev/null || STATUS=$?
    
    if [ $STATUS -eq 0 ] || [ $STATUS -eq 1 ]; then
      if [ $STATUS -eq 1 ]; then
        echo "⚠️  [${folder}] 備份完成（已忽略日誌檔寫入變更）。"
      else
        echo "✓  [${folder}] 備份完成！"
      fi
    else
      echo "❌ [${folder}] 備份發生錯誤！狀態碼: $STATUS (繼續備份其餘項目)"
    fi
  else
    echo "⚠️  提示：找不到路徑 $SRC_PATH，已自動跳過。"
  fi
done

#============ 清理舊備份（保留 30 天內） ============#
echo "--------------------------------------------------"
echo "    開始檢查並清理 30 天前的舊備份檔案...    "
echo "--------------------------------------------------"

find "$BACKUP_DIR" -maxdepth 1 -type f -name "*-backup-*.tar" -mtime +30 -exec rm -f {} \;
find "$BACKUP_DIR" -maxdepth 1 -type f -name "*-SKIPPED.txt" -mtime +30 -exec rm -f {} \;

echo "=================================================="
echo "    所有 Docker 實體資料夾動態備份完畢且清理完成！"
echo "=================================================="
