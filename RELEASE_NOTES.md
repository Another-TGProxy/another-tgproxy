## What's new

**Telegram no longer reports the proxy as misconfigured.** A data centre is
fronted by two hosts that hold different keys — one for chats, one for media —
and the proxy treated them as interchangeable: a session whose first attempt
failed was retried against the other one, which does not know its key. Telegram
answered with a refusal, and on one of its forms both the desktop and the
Android client switch the proxy off by themselves. The Cloudflare relays were
the same mistake from the other side: they front only the first host, so every
media session sent through them was refused. Sessions now keep to their own
host. On a phone where the direct route fails constantly, refusals dropped from
about twelve a minute to under one.

**Android permissions are asked for in the wizard.** The notification and the
battery exemption are what keep the proxy alive once the screen goes off, and
the system dialog used to appear before the app had drawn anything — and again
on every return to it. They now have a step that says what each one is for and
shows whether it is granted, with a button that opens the settings screen where
Android no longer offers a dialog. Setup does not move on without them.

**Setup wizard on first launch.** Walks through the settings that actually need
a decision — updates, port and secret, autostart, where to show status — then
starts the proxy and hands over the connection link. Steps with nothing to ask
skip themselves: no autostart step on Android, no status step where only one
mode is available.

**Media now loads on Android.** The engine looked for the system certificate store
only in the bundle files desktop Linux uses, so on Android every verified
connection failed. That guards the Cloudflare path, which meant only the
datacentres with a direct route worked and everything else fell through to
blocked addresses -- in practice, chats loaded and their images did not. Android
keeps its trust store as a hashed directory, which the engine now reads.

**Blocked addresses no longer stall transfers.** Connecting to an address the ISP
filters used to wait out the kernel's TCP timeout -- over two minutes -- because
such an address swallows the connection attempt instead of refusing it. Media is
fetched over parallel streams, so those stuck attempts were the download: it
stalled rather than failing over to the Cloudflare route. Connections now give up
after five seconds and take the working path.

**The proxy no longer goes quiet after sleep.** On Windows and Android it could
keep reporting "running" while Telegram refused it with invalid proxy settings.
Two causes, both fixed:

- Pre-warmed connections were checked for liveness only when handed out, and the
  check missed a peer that had closed the connection while idle. Such a dead
  connection went to the next session, which then broke right after the
  handshake. Connections are now swept in the background every five seconds, and
  the liveness check catches half-closed sockets.
- Connection age was measured with a clock that stops while the device sleeps,
  so an hour in a pocket counted as seconds and long-dead connections passed as
  fresh. It now uses the wall clock.

**A dropped listening socket is rebuilt.** Windows can tear it down on its own
after a network adapter change; the proxy used to stop accepting connections
silently. It now restores the socket and carries on.

**Android: swiping the app away no longer stops the proxy.** The service used to
shut itself down when the app left the recents list, so Telegram lost the proxy
as soon as the window was dismissed. The proxy now keeps running with its
ongoing notification; stopping it is an explicit action inside the app.

**Update offers are less pushy.** A version you turn down is remembered and not
offered again, and the update dialog no longer pops up right after the setup
wizard has already asked about it.

---

## Что нового

**Telegram больше не считает прокси неправильно настроенным.** У дата-центра два
адреса, и ключи у них разные: один для переписки, другой для медиа. Прокси считал
их взаимозаменяемыми — если первая попытка не удавалась, сессия уходила на
соседний адрес, который её ключа не знает. Telegram отвечал отказом, а на одну из
форм этого отказа и десктопный, и Android-клиент сами отключают прокси. С
ретрансляторами Cloudflare была та же ошибка с другой стороны: за ними стоит
только первый адрес, поэтому все медиа-сессии через них получали отказ. Теперь
сессия остаётся на своём адресе. На телефоне, где прямой маршрут постоянно не
проходит, отказов стало меньше одного в минуту вместо примерно двенадцати.

**Разрешения Android запрашиваются в мастере.** Уведомление и снятие ограничений
батареи — это то, что сохраняет прокси живым после выключения экрана. Раньше
системный диалог выскакивал до того, как приложение успевало нарисовать окно, и
повторялся при каждом возврате в него. Теперь под них отведён шаг, где сказано,
зачем нужно каждое, видно, выдано ли оно, а кнопка ведёт в системные настройки,
если диалог Android больше не показывает. Без них настройка дальше не идёт.

**Мастер первичной настройки.** Проводит по тем настройкам, где действительно
нужно решение: обновления, порт и секрет, автозапуск, где показывать статус.
В конце запускает прокси и выдаёт ссылку для подключения. Шаги, которым нечего
спросить, пропускаются сами: на Android нет шага автозапуска, а шаг статуса
не показывается, если доступен всего один режим.

**На Android снова грузятся картинки.** Движок искал системные сертификаты только
в файлах-связках, как принято в десктопном Linux, поэтому на Android проверка
сертификата не проходила никогда. От неё зависит весь путь через Cloudflare: в
итоге работали лишь датацентры с прямым маршрутом, а остальное упиралось в
заблокированные адреса — переписка открывалась, а изображения нет. На Android
хранилище доверия устроено каталогом, и теперь движок читает и его.

**Заблокированные адреса больше не подвешивают загрузку.** Подключение к адресу,
который фильтрует провайдер, раньше ждало системного таймаута TCP — больше двух
минут: такой адрес не отказывает в соединении, а молча его проглатывает. Медиа
качается несколькими потоками, и эти зависшие попытки и были загрузкой — она
стояла вместо того, чтобы уйти на запасной маршрут через Cloudflare. Теперь
попытка прекращается через пять секунд и работа продолжается рабочим путём.

**Прокси больше не замолкает после сна.** На Windows и Android он мог считаться
работающим, пока Telegram отказывался от него с ошибкой о неверных настройках.
Две причины, обе устранены:

- Заранее прогретые соединения проверялись на живость только в момент выдачи,
  и проверка не замечала, что собеседник закрыл соединение во время простоя.
  Такое мёртвое соединение доставалось следующей сессии, и она обрывалась сразу
  после рукопожатия. Теперь соединения перебираются в фоне каждые пять секунд,
  а проверка живости распознаёт полузакрытые сокеты.
- Возраст соединения считался по часам, которые останавливаются на время сна
  устройства: час в кармане засчитывался за секунды, и давно мёртвые соединения
  проходили как свежие. Теперь используются обычные часы.

**Потерянный слушающий сокет восстанавливается.** Windows может закрыть его сам
после смены сетевого адаптера — раньше прокси молча переставал принимать
подключения. Теперь сокет пересоздаётся, и работа продолжается.

**Android: смахивание приложения больше не выключает прокси.** Служба
останавливала себя, когда приложение уходило из списка недавних, и Telegram
терял прокси сразу после закрытия окна. Теперь прокси продолжает работать
вместе со своим постоянным уведомлением, а выключается явно — из приложения.

**Обновления навязываются меньше.** Версия, от которой вы отказались,
запоминается и больше не предлагается, а диалог обновления не появляется сразу
после мастера, который уже про него спрашивал.
