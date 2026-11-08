# vpn-node

VPN-нода одним плейбуком: VLESS + XHTTP (packet-up) за nginx с TLS, 3x-ui в Docker.
Снаружи только nginx (сертификат Let's Encrypt, HTTP/2, страница-заглушка, чужой SNI — обрыв
handshake); Xray и панель слушают 127.0.0.1.

## Новая нода

1. ВМ с Debian 13, твой ключ у root (`ssh root@<домен>` должен пускать без пароля).
2. A-запись домена → IP ВМ (сертификат выпускается по HTTP, без неё certbot упадёт).
3. Добавить домен в `inventory.yml` (первый раз: `cp inventory.example.yml inventory.yml`):
   ```yaml
   all:
     hosts:
       node1.example.org:
       node2.example.org:
   ```
4. Запуск:
   ```sh
   cd ~/vpn-node
   ansible-playbook site.yml -l node2.example.org
   ```
5. Результат — в `credentials/<домен>/`:
   - `links.txt` — vless-ссылки клиентов (в podkop / v2rayN / Hiddify);
   - `panel.txt` — как зайти в панель.

Повторный запуск безопасен: меняется только то, что разошлось с описанием.
Проверить без изменений: `ansible-playbook site.yml -l <домен> --check --diff`.

## Клиенты (юзеры VPN)

Общий список для всех нод — `xui_clients` в `group_vars/all.yml`.
Свой список для одной ноды — файл `host_vars/<домен>.yml`:
```yaml
xui_clients:
  - home-router
  - friend-router
  - phone
```
Затем:
```sh
ansible-playbook site.yml -l <домен> --tags xui
```
Плейбук досоздаст недостающих клиентов и перепишет `links.txt`. Имя из списка — только метка
(комментарий в панели); в панели и в ссылке клиент получает случайное имя вида `node1-k3x9q0b2mz`.
UUID и случайное имя постоянные (выводятся из секрета ноды и метки). Удалять или отключать
клиента — в панели.

## Панель

```sh
ssh -N -L 5223:127.0.0.1:5223 root@<домен>     # окно держать открытым
```
Адрес, логин и пароль — в `credentials/<домен>/panel.txt`.

## Частичный запуск

| тег     | что                                                              |
|---------|------------------------------------------------------------------|
| `base`  | hostname, пакеты, автообновления, sshd (только ключи), nftables  |
| `root`  | zsh + oh-my-zsh (darkblood), ключи root                          |
| `nginx` | nginx, сертификат, заглушка                                      |
| `xui`   | 3x-ui, инбаунд, клиенты, links.txt                               |

Пример: `ansible-playbook site.yml -l <домен> --tags nginx`.

## Настройки (`group_vars/all.yml`, переопределяются в `host_vars/<домен>.yml`)

- `ssh_allow` — пусто: 22 открыт всем; иначе список IPv4, например `[1.2.3.4/32]`;
- `ssh_keys` — ключи root (по умолчанию `~/.ssh/id_ed25519.pub`);
- `xui_image` — версия 3x-ui; обновление: поменять тег и запустить с `--tags xui`;
- `zsh_theme`, `zsh_plugins`.

## Страница-заглушка

По корню сайта открывается заглушка. Своя для ноды — файлы в `site/<домен>/` (`index.html` и что
угодно ещё), они копируются как есть. Если каталога нет — стандартная страница nginx из Debian.
Не используй одну и ту же самодельную страницу на нескольких нодах: по ней ноды связываются между
собой.

## Локальные файлы (в .gitignore)

`inventory.yml`, `host_vars/`, `credentials/`, `site/` — в них реальные домены и секреты.

## Секреты

`credentials/<домен>/` создаётся при первом запуске и есть только локально (в .gitignore):
путь XHTTP, логин/пароль/путь панели, seed UUID. **Не терять**: без `client_seed` и `xhttp_path`
плейбук сгенерирует новые, и ссылки клиентов перестанут работать.

## Не автоматизировано

Особенности сети хостера (например, NetworkManager вместо ifupdown).
