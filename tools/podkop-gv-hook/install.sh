#!/bin/sh
# Хук podkop: видео YouTube с серверов Google -> VPN, кэши провайдера остаются как есть.
#   sh install.sh [путь/к/sing-box-hook.jq]   - установить или обновить хук (по умолчанию рядом со скриптом)
#   sh install.sh remove                      - убрать хук и подключение
# Запускать отвязанно от SSH (см. README). Лог: /root/gv-hook.log. При поломке сети всё откатывается.
HOOK=/etc/podkop/sing-box-hook.jq
BIN=/usr/bin/podkop
L=/root/gv-hook.log
TS=$(date +%Y%m%d-%H%M%S)
log(){ echo "$(date +%T) $*" | tee -a $L; }
die(){ log "СТОП: $*"; exit 1; }
net(){ pidof sing-box >/dev/null && nslookup github.com 127.0.0.42 2>/dev/null | grep -q "^Address" \
  && [ "$(curl -s -o /dev/null -m 8 -w %{http_code} https://www.google.com/generate_204)" = 204 ]; }
has_yt(){ jq -e '.route.rules[] | select(.action=="route" and ((.rule_set // []) | if type=="array" then . else [.] end | any(.[]; contains("youtube"))))' /etc/sing-box/config.json >/dev/null 2>&1; }
hooked(){ jq -e '.route.rules[] | select(.type=="logical" and (.rules[]?.domain_suffix // [] | index("googlevideo.com")))' /etc/sing-box/config.json >/dev/null 2>&1; }

[ -x $BIN ] || die "нет $BIN - podkop не установлен?"
command -v jq >/dev/null || die "нужен jq"
cp $BIN /root/podkop.bin.bak-$TS
[ -f $HOOK ] && cp $HOOK /root/sing-box-hook.jq.bak-$TS
rollback(){ log "=== ОТКАТ"; cp /root/podkop.bin.bak-$TS $BIN
  if [ -f /root/sing-box-hook.jq.bak-$TS ]; then cp /root/sing-box-hook.jq.bak-$TS $HOOK; else rm -f $HOOK; fi
  podkop restart >/dev/null 2>&1; sleep 12; net && log "после отката сеть работает" || log "после отката сеть НЕ работает, смотри logread"; exit 1; }
unhook(){ # удаляет блок подключения (и с метками, и старый вариант без меток)
  sed -i -e '/# >>> gv-hook/,/# <<< gv-hook/d' $BIN
  sed -i -e '/# локальный хук (не из пакета): \/etc\/podkop\/sing-box-hook.jq/,/^    fi$/d' $BIN; }

if [ "$1" = remove ]; then
  unhook; rm -f $HOOK
  sh -n $BIN || rollback
  log "podkop restart"; podkop restart >/dev/null 2>&1
  for i in $(seq 1 30); do sleep 3; net && { log "=== хук удалён, сеть работает"; exit 0; }; done
  rollback
fi

SRC=${1:-$(dirname "$0")/sing-box-hook.jq}
[ -f "$SRC" ] || die "нет файла хука $SRC"
echo '{"route":{"rules":[]},"outbounds":[]}' | jq -f "$SRC" >/dev/null || die "$SRC не разбирается jq"
mkdir -p /etc/podkop
if ! grep -q 'sing-box-hook.jq' $BIN; then
  grep -q '^sing_box_save_config() {$' $BIN || die "в $BIN нет sing_box_save_config() - другая версия podkop?"
  cat > /tmp/gv-hookline <<'H'
    # >>> gv-hook: локальный хук (не из пакета) /etc/podkop/sing-box-hook.jq; при ошибке jq конфиг не трогается
    if [ -f /etc/podkop/sing-box-hook.jq ]; then
        local _hooked
        _hooked=$(echo "$config" | jq -f /etc/podkop/sing-box-hook.jq 2>/dev/null) && [ -n "$_hooked" ] && config="$_hooked"
    fi
    # <<< gv-hook
H
  sed -i '/^sing_box_save_config() {$/r /tmp/gv-hookline' $BIN; rm -f /tmp/gv-hookline
  log "подключение хука добавлено в $BIN"
fi
sh -n $BIN || rollback
cp "$SRC" $HOOK
log "podkop restart"; podkop restart >/dev/null 2>&1
for i in $(seq 1 30); do sleep 3; if net; then
  if has_yt && ! hooked; then log "сеть ок, но правила хука нет в конфиге"; rollback; fi
  has_yt && log "=== OK: хук работает, сеть работает" || log "=== OK: хук установлен, но в podkop нет списка youtube - правило не добавлено"
  exit 0; fi; done
rollback
