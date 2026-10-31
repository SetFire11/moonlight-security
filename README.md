# Moonlight Security

Одно меню на сервере. Три защиты включаются отдельными пунктами и не настраиваются одним прогоном.

1. **Traffic Guard** — блок сканеров. Списки лежат в `trafficguard/lists` и никуда не скачиваются.
2. **AntiScan** — лимиты, Fail2Ban, CrowdSec, подсети РКН, BBR.
3. **Server Shield** — файрвол, DDoS, SSH, nginx.

## Установка

На Debian или Ubuntu, от root, из каталога репозитория:

```bash
sudo bash install.sh
moonlight
```

`install.sh` только ставит команду `moonlight`. Правила файрвола сами не включаются.

Когда репозиторий будет на GitHub:

```bash
git clone https://github.com/SetFire11/moonlight-security.git
cd moonlight-security
sudo bash install.sh
```

## Списки

Пункт 1 берёт списки только из `trafficguard/lists`.

Свой адрес или адрес партнёра, если он есть в списке, положи точной строкой в `trafficguard/exclude.list`. Иначе обратный путь до сервера можно отрезать. Пример: `trafficguard/exclude.list.example`.

Повторное обновление списков: меню Traffic Guard, пункт «Обновить списки», или `rknpidor`.

## Важно

Server Shield может отключить вход по паролю. Запускай его, когда SSH-ключ уже на сервере.

RemnaNode AntiScan после применения ждёт подтверждения из новой SSH-сессии. Без подтверждения настройки откатываются.
