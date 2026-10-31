<p align="center">
  <img src="assets/banner.svg" alt="Moonlight Security" width="880">
</p>

<p align="center">
  Защита Debian и Ubuntu из одного меню.<br>
  Каждая защита включается своим пунктом.<br>
  v1.0
</p>

## Установка

На сервере, от root:

```bash
git clone https://github.com/SetFire11/moonlight-security.git
cd moonlight-security
sudo bash install.sh
moonlight
```

`install.sh` ставит команду `moonlight`. Файрвол включается уже из меню.

## Меню

| Пункт | Раздел | Что делает |
| --- | --- | --- |
| 1 | Traffic Guard | 1 установка, 2 проверка, 3 выход |
| 2 | AntiScan | Лимиты, Fail2Ban, CrowdSec, подсети РКН, BBR |
| 3 | Server Shield | Файрвол, DDoS, SSH, nginx |
| 4 | Статус | Память, диск, порты, состояние ноды |
| 5 | Нода | Контейнеры, логи, перезапуск |
| 6 | Обновление | Свежая версия с GitHub, исключения сохраняются |

Обновить списки сканеров: меню Traffic Guard или команда `rknpidor`.

## Перед включением

Свой адрес или адрес партнёра, если он есть среди сканеров, запиши точной строкой в `trafficguard/exclude.list`. Иначе обратный путь до сервера можно отрезать. Пример: `trafficguard/exclude.list.example`.

Server Shield может отключить вход по паролю. Запускай его, когда SSH-ключ уже на сервере.

AntiScan после применения ждёт подтверждения из новой SSH-сессии. Без подтверждения настройки откатываются.

## Лицензия

[MIT](LICENSE)
