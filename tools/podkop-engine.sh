#!/bin/sh
# Замена стокового sing-box на podkop-engine с авто-откатом (OpenWrt 25.12, apk).
#   sh podkop-engine.sh prep      - только проверки и загрузка, роутер не меняет
#   sh podkop-engine.sh swap      - замена; запускать отвязанно (см. README)
#   sh podkop-engine.sh rollback  - вернуть стоковый sing-box
VER=1.14.4-r21
DIR=/root/pe
log(){ echo "$(date +%T) $*"; }
die(){ log "СТОП: $*"; exit 1; }

net(){ curl -s -o /dev/null -m 8 -w "%{http_code}" https://www.google.com/generate_204 2>/dev/null; }
healthy(){
  pidof sing-box >/dev/null || { echo "  sing-box не запущен"; return 1; }
  nslookup github.com 127.0.0.42 2>/dev/null | grep -q "^Address" || { echo "  DNS podkop (127.0.0.42) не отвечает"; return 1; }
  [ "$(net)" = 204 ] || { echo "  нет интернета"; return 1; }
}
wait_healthy(){
  for i in $(seq 1 40); do sleep 3; healthy >/tmp/pe-h.out 2>&1 && { log "всё работает через $((i*3)) с"; return 0; }; done
  cat /tmp/pe-h.out; return 1
}

rollback(){
  STOCK=$(ls $DIR/sing-box-[0-9]*.apk 2>/dev/null | head -1)
  [ -n "$STOCK" ] || die "нет $DIR/sing-box-*.apk для отката"
  log "откат на стоковый sing-box"
  podkop stop >/dev/null 2>&1
  sed -i -e '/^!podkop-engine$/d' -e 's/^sing-box><.*/sing-box/' /etc/apk/world
  # пакет из apk fetch проверяется по индексу репозитория, из файла - только с --allow-untrusted
  apk add --allow-untrusted "$STOCK" '!podkop-engine' 2>&1 | tail -3
  if ! sing-box version 2>/dev/null | head -1 | grep -qv pdk; then
    log "из файла не встал, пробую из репозитория"
    apk update >/dev/null 2>&1; apk add sing-box '!podkop-engine' 2>&1 | tail -3
  fi
  [ -f $DIR/sing-box.config.bak ] && cp $DIR/sing-box.config.bak /etc/config/sing-box
  podkop start >/dev/null 2>&1
  wait_healthy && log "ОТКАТ OK: $(sing-box version | head -1)" || log "ОТКАТ: всё ещё не работает, смотри logread"
}

prep(){
  command -v apk >/dev/null || die "нет apk - это скрипт для OpenWrt 25.12"
  PK=$(apk list -I podkop 2>/dev/null | awk '{print $1}')
  [ -n "$PK" ] || die "podkop не установлен"
  log "$PK (xhttp-ссылки понимает с 0.7.24)"
  log "сейчас: $(sing-box version 2>/dev/null | head -1)"
  sing-box version 2>/dev/null | grep -q pdk && die "podkop-engine уже стоит"
  ARCH=$(. /etc/os-release; echo "$OPENWRT_ARCH")
  [ -n "$ARCH" ] || ARCH=$(awk '/openwrt_core/{n=split($3,a,"/"); print a[n-1]}' /etc/apk/repositories.d/distfeeds.list 2>/dev/null | head -1)
  [ -n "$ARCH" ] || die "не определил архитектуру"
  log "архитектура: $ARCH"
  FREE=$(df -k /usr/bin | awk 'NR==2{print $4}')
  log "свободно во flash: $((FREE/1024)) МБ, RAM: $(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) МБ доступно"
  [ "$FREE" -gt 61440 ] || die "во flash меньше 60 МБ, движок с пакетами для отката не поместится"
  mkdir -p $DIR && cd $DIR || exit 1

  ENG=podkop-engine_${VER}_openwrt_${ARCH}.apk
  if [ ! -s "$ENG" ]; then
    log "качаю $ENG"
    curl -fL -m 300 -o "$ENG" "https://github.com/podkop-net/podkop-engine/releases/download/v$VER/$ENG" \
      || { rm -f "$ENG"; die "не скачался с GitHub; скачай на ноутбуке и положи в $DIR/$ENG через scp"; }
  fi
  if ! ls sing-box-[0-9]*.apk >/dev/null 2>&1; then
    log "качаю стоковый sing-box для отката"
    apk update >/dev/null 2>&1; apk fetch -o $DIR sing-box 2>&1 | tail -1
    ls sing-box-[0-9]*.apk >/dev/null 2>&1 || die "стоковый sing-box не скачался, без него откатываться не на что"
  fi
  cp /etc/config/podkop $DIR/podkop.config.bak
  cp /etc/config/sing-box $DIR/sing-box.config.bak

  log "пробный запуск движка из /tmp (ничего не устанавливается)"
  rm -rf /tmp/pe-x; mkdir /tmp/pe-x
  apk extract --allow-untrusted --destination /tmp/pe-x "$ENG" >/dev/null 2>&1
  /tmp/pe-x/usr/bin/sing-box version 2>/dev/null | grep -q pdk || { rm -rf /tmp/pe-x; die "движок не запускается на этом процессоре"; }
  /tmp/pe-x/usr/bin/sing-box check -c /etc/sing-box/config.json >/tmp/pe-check.out 2>&1; OK=$?
  grep -v WARN /tmp/pe-check.out
  rm -rf /tmp/pe-x /tmp/pe-check.out
  [ $OK = 0 ] || die "текущий конфиг podkop движку не нравится, пришли вывод выше"
  log "интернет сейчас: $(net)"
  log "=== ПОДГОТОВКА OK, можно swap"
}

swap(){
  ENG=$(ls $DIR/podkop-engine_*.apk 2>/dev/null | head -1)
  [ -n "$ENG" ] && ls $DIR/sing-box-[0-9]*.apk >/dev/null 2>&1 || die "сначала prep"
  [ "$(net)" = 204 ] || die "интернет не работает уже ДО замены, не трогаю"
  log "было: $(sing-box version | head -1)"
  # без этого apk удалит kmod-ы стокового sing-box как ненужные, и откат без сети не встанет
  KM=$(apk info -R sing-box 2>/dev/null | grep '^kmod-')
  [ -n "$KM" ] && apk add $KM 2>&1 | tail -1
  sed -i -e '/^!podkop-engine$/d' -e 's/^sing-box><.*/sing-box/' /etc/apk/world
  apk add --allow-untrusted "$ENG" 2>&1 | tail -3
  log "стало: $(sing-box version 2>&1 | head -1)"
  podkop restart >/dev/null 2>&1
  if sing-box version 2>/dev/null | grep -q pdk && wait_healthy; then
    logread | grep -iE "podkop|sing-box" | grep -iE "error|fatal" | tail -5 | cut -c1-200
    log "=== ДВИЖОК OK"
  else
    logread | grep -iE "podkop|sing-box" | grep -iE "error|fatal" | tail -8 | cut -c1-200
    rollback
    log "=== БЫЛ ОТКАТ"
  fi
}

case "$1" in
  prep) prep ;;
  swap) swap ;;
  rollback) rollback ;;
  *) echo "usage: $0 prep|swap|rollback" ;;
esac
