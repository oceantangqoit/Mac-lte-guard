# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>¿Se te desconecta el adaptador de red USB cuando cierras la tapa del Mac? Se arregla solo al despertar, sin volver a enchufarlo.</b><br>
  <sub>Herramienta de vigilancia para adaptadores de red USB, residente en la barra de menús · Swift nativo · Sin dependencias · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <b>Español</b> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.rw.md">Ikinyarwanda</a>
</p>

---

## El problema

Muchos módems LTE USB y adaptadores Ethernet USB se quedan «colgados» después de que el Mac entra en suspensión al cerrar la tapa: el LED sigue encendido, la interfaz sigue apareciendo en el sistema, pero no hay conexión. **Hay que desenchufarlo y volver a enchufarlo** para que funcione otra vez.

La causa es que, durante la suspensión, macOS no corta la alimentación USB (el VBUS lo gestiona directamente el firmware del SMC y el software no puede desactivarlo), mientras que la sesión USB del lado del dispositivo ya ha caducado. Reiniciar el servicio de red no sirve de nada, porque lo que hay que reiniciar es la capa USB.

## Quién lo necesita

Si tu Mac se conecta a Internet mediante un **adaptador de red USB externo**, es probable que te topes con este problema:

- 🚁 **Transmisión de vídeo de dron convertida a LTE** — montajes como pasar el enlace de vídeo del DJI de primera generación a red celular, con el Mac vigilando durante horas con un módem 4G/5G conectado
- 📡 **Módems USB LTE / 4G / 5G, routers de bolsillo, módulos celulares USB** — trabajo en exteriores, vehículos, embarcaciones, ferias, oficinas temporales
- 🔌 **Adaptadores USB-C / Thunderbolt a Ethernet** — el Mac no tiene puerto de red y necesitas cable en salas de reuniones, centros de datos o en casa del cliente
- 🧩 **Adaptadores de red integrados en docks** — Belkin, Plugable, Anker, UGREEN, CalDigit, etc.
- 🎥 **Emisiones en directo, streaming RTMP y administración remota** que dependen de una subida estable
- 🖥 **Routers por software / Raspberry Pi / equipos industriales** conectados directamente al Mac por USB para depuración

El denominador común: cierras la tapa una vez y al volver no hay red; el LED sigue encendido y **solo se arregla desenchufando y volviendo a enchufar**.

### No solo adaptadores de red

Ese mismo «se cuelga al despertar y solo se arregla con un tirón físico del cable» es muy habitual en otros dispositivos USB. Hay abundante documentación en la [comunidad oficial de Apple](https://discussions.apple.com/thread/7745583), en [MacRumors](https://forums.macrumors.com/threads/mac-mini-m1-usb-ports-not-working-after-wake-from-sleep.2326616/) y en la [base de conocimiento de Plugable](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos): interfaces de audio, cámaras, discos externos, lectores de tarjetas y los distintos componentes de un dock caen todos en lo mismo.

Como el mecanismo de fondo es idéntico, el menú de esta herramienta incluye **«Restablecer dispositivo USB»**: lista todos los dispositivos USB conectados y, al elegir uno, le aplica un desenchufado por software sin que tengas que estirarte hasta el cable. Fuera del adaptador de red, los demás dispositivos requieren activación manual por ahora (la detección automática solo cubre la red, porque «hay conexión o no la hay» tiene un criterio claro, mientras que en una cámara o una interfaz de audio es muy difícil decidir automáticamente si están colgadas).

> ⚠️ Antes de usarlo con discos externos u otros dispositivos de almacenamiento, detén la lectura/escritura y expúlsalos; de lo contrario, puedes corromper los datos.

## Si has llegado aquí buscando

Las formas de describirlo que aparecen abajo son las que se usan realmente en los foros en español. Si has buscado por cualquiera de ellas, esta herramienta se escribió justo para eso.

### Cómo se pregunta en los foros en español

> el Mac no reconoce el cable de red tras la suspensión · el adaptador Ethernet USB deja de funcionar al despertar · me aparece «sin conexión» · no reacciona y permanece sin conexión · hay que desconectar y volver a conectar el adaptador · hay que desenchufarlo y enchufarlo otra vez para que vuelva · el LED está encendido pero no hay red · la interfaz existe pero no responde al ping · el disco duro externo se desconecta solo cuando el Mac entra en reposo · se expulsa solo el disco al suspender · aviso de «expulsión incorrecta del disco» al despertar · el hub USB-C deja de verse tras cerrar la tapa · los puertos USB-C no responden al salir de la suspensión · el módem LTE se desconecta al cerrar la tapa · accesorios USB desactivados

Nota de vocabulario: en España el ajuste de Apple se llama **reposo** y en Latinoamérica **suspensión**; en los foros conviven «tras suspender», «en reposo», «al despertar» y «al salir de la suspensión» para lo mismo.

### Títulos reales de hilos

Recogidos literalmente de la Comunidad de Apple en español y de medios especializados:

> `Problema hub USB-C ethernet en MacBook Air m2` · `Disco duro externo se desconecta solo y no puedo ver los archivos. MacBook Air` · `Macbook Pro 13" M1, expulsa los discos` · `Se expulsa solo mi disco duro externo` · `Disco Duro Externo Se Desconecta Solo` · `Mi disco externo se desconecta solo` · `Disco duro WD se expulsa sólo` · `Mac no puede ver disco duro externo` · `ACCESORIOS USB DESACTIVADOS` · `No funciona mi 2do puerto USB C` · `no funciona puerto ethernet imac` · `Fallo USB MacBook: bug de Catalina y posible solución` · `USB-C no funciona en Mac: 6 soluciones probadas` · `Qué hacer cuando los puertos USB-C del MacBook no funcionan` · `¿Problemas al Conectar el Adaptador Ethernet en tu Macbook? Posibles Causas y Soluciones`

Citado literalmente del hilo del hub USB-C en la Comunidad de Apple:

> «me aparecía **sin conexión**» … «**no reacciona y permanece sin conexión**»
> — [Problema hub USB-C ethernet en MacBook Air m2](https://communities.apple.com/es/thread/254858518), Comunidad de Apple

Y el paso que Apple recomienda primero, y que en este caso hay que repetir cada vez:

> «**desconectar y volver a conectar** el dispositivo externo al Mac»
> — Comunidad de Apple (respuesta estándar de los especialistas)

### Combinaciones de búsqueda habituales

En español:

> `adaptador USB Ethernet no funciona tras suspender mac` · `mac pierde la red al salir de la suspensión` · `desconectar y volver a conectar adaptador ethernet mac` · `dock USB-C no reconocido tras suspensión mac` · `disco duro externo no se monta después de suspender mac` · `se expulsa solo el disco duro externo mac reposo` · `puertos USB no funcionan al despertar macbook` · `módem 4G LTE se desconecta al cerrar la tapa mac` · `reiniciar puerto USB macOS terminal`

En inglés (esta herramienta sirve igualmente):

> `usb ethernet adapter not working after sleep mac` · `macbook ethernet doesn't wake up after sleep` · `usb-c ethernet adapter stops working after lid close` · `mac dock ethernet not detected after wake` · `lte modem disconnects after macbook sleeps` · `have to unplug and replug ethernet adapter macos`

### Por tipo de dispositivo

| Tu equipo | Descripción habitual |
|---|---|
| Adaptador Ethernet USB / USB-C | el LED está encendido pero no hay red, aparece «sin conexión», la interfaz `en5` sigue ahí pero el ping no pasa, hay que desconectarlo y volver a conectarlo |
| Módem LTE / 4G / 5G, pincho USB | se desconecta al cerrar la tapa, sin datos al despertar, hay que sacarlo y volver a ponerlo para que marque otra vez |
| Dock / base de conexión (Belkin, Plugable, Anker, CalDigit, OWC, Satechi) | al despertar no se reconoce ningún dispositivo del dock, hay que desconectar el dock entero y volver a conectarlo |
| Disco duro externo / SSD | no se monta tras la suspensión, aviso de «expulsión incorrecta del disco», «se desconecta solo», solo reaparece al volver a enchufarlo |
| Webcam / capturadora / interfaz de audio | desaparece de la lista de dispositivos al despertar, no se puede seleccionar en el programa |
| Lector de tarjetas / mochila USB / teclado y ratón | no responde al despertar, basta con desconectar y volver a conectar una vez |

### Chips más citados

> ASIX `AX88179` / `AX88179A` · Realtek `RTL8153` · Realtek `RTL8156` de 2,5 G · Quectel `EC25` · series `CM3xx` · Intel `I225-V` (a través de un dock Thunderbolt)

### Qué tan extendido está el problema

En la comunidad oficial de Apple, en MacRumors y en la base de conocimiento de Plugable hay consultas del mismo tipo repartidas a lo largo de años, tanto en Intel como en Apple Silicon:

- [Ethernet USB-C adapter doesn't wake up after sleep](https://forums.macrumors.com/threads/ethernet-usb-c-adapter-doesnt-wake-up-after-sleep.2220969/) — MacRumors
- [Ethernet adapter doesn't want to wake up after sleep](https://discussions.apple.com/thread/8272273) — Comunidad oficial de Apple
- [MacBook Air 2020 USB LAN issue after sleep](https://discussions.apple.com/thread/255925525) — Comunidad oficial de Apple
- [Usb ethernet adapter is not working after sleep](https://discussions.apple.com/thread/7686532) · [Ethernet not waking after sleep](https://discussions.apple.com/thread/250166501) · [Ethernet reset/disconnect on wake-up](https://discussions.apple.com/thread/251074085) · [Ethernet disconnected after sleep](https://discussions.apple.com/thread/8425667)
- [Devices are not detected after waking from sleep on macOS](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) — Base de conocimiento oficial de Plugable

### Por qué no funcionan las «soluciones oficiales» habituales

| Lo que suelen recomendar | Por qué no sirve en este caso |
|---|---|
| Restablecer SMC / NVRAM | En los modelos con Apple Silicon **el restablecimiento del SMC ni siquiera existe**; y aunque lo hagas en un Intel, la próxima vez que cierres la tapa vuelve a pasar: no ataca la causa |
| Desactivar «Activar por acceso de red» (Wake for network access) | Ese ajuste controla que el equipo *se despierte* por la red durante la suspensión, algo muy distinto de que la sesión USB caduque tras despertar |
| Apagar del todo y reiniciar / actualizar el sistema | Funciona, pero es absurdo: ¿vas a reiniciar el ordenador cada vez que cierres la tapa? |
| Desenchufar el cable de red en lugar del adaptador | Se recomienda una y otra vez en los foros, pero en la práctica no funciona (palabras textuales del autor del hilo original: «también lo probé, no sirve») |
| **Desenchufar el adaptador USB y volver a enchufarlo** | El único método que funciona de forma fiable — **y es exactamente lo que esta herramienta hace automáticamente por software** |

## La solución

LTE Guard es una herramienta residente en la barra de menús que escucha los eventos de despertar del sistema: al despertar aplica **de inmediato** un **desenchufado por software (USBDeviceReEnumerate)** al dispositivo USB vigilado mediante IOKit, equivalente a hacerlo con la mano. Sin comprobaciones previas de «¿hará falta reparar?»: quien instala esta herramienta ya es víctima del dispositivo zombi, y comprobar solo es perder el tiempo. La recuperación solo cuenta cuando **la puerta de enlace responde de verdad al ping**, normalmente **en unos 8 segundos**, rozando el límite físico de un desenchufado manual.

- 🎯 **Sin marcas predefinidas** — al seleccionar el adaptador detecta su VID/PID automáticamente; no hay lista interna de dispositivos
- 🖇 **Vigila varios adaptadores a la vez** — marca tantos como quieras; cada uno se comprueba y se repara por su cuenta, en paralelo
- 🔌 **También sirve para adaptadores no USB** — recurre automáticamente a reiniciar el servicio de red
- 🛠 **Enganches de comandos en dos fases** — unos comandos se ejecutan **en cuanto se detecta el corte** (p. ej. abrir el panel de Red y ver la reparación en directo) y otros **tras la recuperación** (reconectar un proxy, volver a marcar, etc.)
- 🔔 **Notificaciones solo con buenas noticias** — recibes exactamente una notificación, cuando el adaptador vuelve *y* se ha comprobado que Internet funciona de verdad (con el tiempo empleado); reparación en curso, sin Internet y fallo se expresan solo en el icono de la barra de menús (giro / `✓8s` / `⚠︎` / `✕`)
- 🌍 **Multilingüe** — de dialectos chinos a lenguas minoritarias; interfaz y registros totalmente localizados; sigue automáticamente al sistema y también se puede elegir a mano en el menú
- 🪶 **Cero dependencias** — una sola app: sin demonios instalados, sin Homebrew y sin ninguna elevación de privilegios

## Instalación

**Opción 1: descargar el paquete** ([Releases](../../releases))

- `LTEGuard-x.y.z.dmg` — arrástralo a Aplicaciones
- `LTEGuard-x.y.z.pkg` — doble clic para instalar; configura el arranque automático

Si al abrirlo por primera vez aparece «no se puede verificar el desarrollador» (el aviso normal de una app sin firmar): **clic derecho en la app → Abrir → Abrir de nuevo**, o ejecuta en el Terminal

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

**Opción 2: compilarlo tú mismo** (requiere las herramientas de línea de comandos de Xcode)

```bash
git clone https://github.com/oceantangqoit/Mac-lte-guard.git
cd Mac-lte-guard && ./build.sh
```

El resultado queda en `dist/`. Para generar el icono hace falta `brew install librsvg`, pero sin él también compila (la app usa el icono por omisión).

## Primer uso

La primera vez que la abras tras instalarla verás un asistente: **explicación → elegir el adaptador que quieres vigilar → preguntar si quieres el arranque automático**. Solo hay que ir siguiendo los pasos.

Si algo falla, pulsa antes que nada **Ejecutar diagnóstico** en el menú: revisa punto por punto y te dice directamente cómo arreglarlo.

| Punto del diagnóstico | Qué significa si falla y qué hacer |
|---|---|
| Ubicación de instalación | Si aparece en `/Volumes/…`, estás ejecutándola directamente desde el DMG: arrastra primero la app a «Aplicaciones» |
| Atributo de cuarentena (Gatekeeper) | Marca normal en apps sin firmar. Si no abre: **clic derecho en la app → Abrir → Abrir**, o `xattr -dr com.apple.quarantine /Applications/LTEGuard.app` |
| Herramienta de reparación | Si usbreset está disponible; normalmente se instala junto con la app y no hay que instalarlo aparte |
| Objetivo vigilado | Si ya has elegido adaptador y si la interfaz existe realmente (te avisa si has cambiado de adaptador) |
| Arranque automático | Si está desactivado, no se ejecutará sola tras reiniciar; puedes activarlo desde el menú con un clic |

**Sobre los permisos**: esta herramienta **no necesita ninguna elevación de privilegios**: nada de Accesibilidad, nada de acceso al disco, nada de root y ningún demonio en segundo plano.

## Uso

1. Al arrancar aparece un icono de señal en la barra de menús
2. Abre el menú → **Elegir objetivo a curar…** → marca tu adaptador — **puedes marcar varios** (los marcados con `· USB` admiten desenchufado por software)
3. Listo. A partir de ahí, cierra la tapa y ábrela: si se corta, se arregla solo

Resto de opciones del menú:

| Opción | Función |
|---|---|
| Comprobar y reparar ahora | Lanza una comprobación manual |
| Ver registro | Abre `~/Library/Application Support/LTE Guard/lte-guard.log` |
| Arranque automático | Interruptor, modificable en cualquier momento (también si instalaste desde el DMG) |
| Ejecutar diagnóstico | Autocomprobación punto por punto con su solución |
| Comando tras la recuperación… | Enganches en dos fases: «al detectar el corte» (p. ej. abrir el panel de Red para ver la reparación) y «tras la recuperación» (p. ej. reconectar un proxy) — un comando por línea, ejecutados en orden, más opciones habituales que basta con marcar |
| Restablecer dispositivo USB | Lista todos los dispositivos USB y les aplica un desenchufado por software con un clic: vale igual para interfaces de audio, cámaras, discos y docks |
| Icono en la barra de menús | Mostrar siempre / Mostrar solo ante anomalías / Ocultar (**si lo ocultas, basta con abrir la app otra vez desde «Aplicaciones» para recuperarlo**) |
| Abrir carpeta de configuración | Abre en el Finder la configuración, el registro y la carpeta de idiomas |
| Idioma | Cambio de idioma; desde el submenú puedes editar el idioma actual o abrir la carpeta de idiomas |

## Idiomas de derecha a izquierda (RTL)

Incluye 4 idiomas de escritura de derecha a izquierda: **العربية** (árabe), **עברית** (hebreo), **فارسی** (persa) y **اردو** (urdu).

Como el cambio de idioma está implementado dentro de la propia app (leyendo `lang/*.ini`) y no mediante el mecanismo de localización `.lproj` de macOS, el sistema no refleja la interfaz automáticamente. Por eso se han añadido dos capas de tratamiento:

1. **Reflejo de la interfaz**: al cambiar a un idioma RTL, los menús y submenús se ponen en `.rightToLeft`: texto alineado a la derecha, iconos desplazados a la derecha y flechas de submenú invertidas.
2. **Aislamiento del texto bidireccional**: los valores que se insertan en los textos (nombre de interfaz `en2`, `2c7c:0125`, nombres de servicio, etc.) son letras latinas y cifras; incrustarlos directamente en una frase en árabe hace que el algoritmo BiDi de Unicode los reordene y **los dos puntos y los paréntesis acaben en el lado equivocado**. Por eso, cada sustitución de marcador de posición se envuelve en `U+2068 FSI` / `U+2069 PDI` (la práctica recomendada por el W3C i18n), de modo que cada valor insertado sea una unidad direccional independiente.
3. El campo «Comando tras la recuperación» se fuerza a alineación izquierda: un comando de shell siempre es texto latino y alinearlo a la derecha lo hace más difícil de leer.

## Varios idiomas

Incluye numerosos idiomas; se elige automáticamente según el idioma del sistema al arrancar y también puedes cambiarlo a mano en el menú «Idioma» (recuerda tu elección).

Los idiomas añadidos más tarde se tradujeron con ayuda de IA y todavía no los ha revisado un hablante nativo; así consta en la cabecera del archivo. **Si ves una expresión poco natural, corrige esa línea y envía un PR**: es la forma más sencilla de contribuir.

**Retocar la redacción de un idioma existente**: el menú «Idioma → Editar idioma actual…» **copia el ini del idioma actual desde dentro de la app a tu carpeta de idiomas y lo abre directamente**; reinicia la app para aplicar los cambios. Esa copia tiene prioridad sobre la versión integrada y **no se sobrescribe al actualizar la app**.

Al exportarlo aparece primero un aviso y se hace una cosa: **eliminar el nombre y los datos de contacto del autor original y sustituirlos por los tuyos**. Es decir, desde el momento de la exportación esa copia es tu propio archivo, respondes tú de su contenido y no tiene nada que ver con el autor original; no escribas en él contenido ilegal, ofensivo o que vulnere derechos de terceros. El archivo se guarda solo en tu ordenador y no se sube a ningún sitio.

**Añadir un idioma nuevo**: menú «Idioma → Abrir carpeta de idiomas…» (deja automáticamente dos plantillas, `zhs.template.ini` en chino simplificado y `en.template.ini` en inglés); copia una, renómbrala con el código del idioma de destino (por ejemplo `nl.ini`) y traduce lo que hay a la derecha del signo igual.

El orden de búsqueda de los archivos de idioma es: **tu carpeta de idiomas → los integrados en la app**; ante nombres iguales manda el tuyo. Si terminas un archivo, envíalo por PR para que beneficie a todos los que hablan ese idioma.

**Formato del archivo de idioma**: un INI por idioma, en el directorio `lang/`, con códigos numéricos como claves:

```ini
[meta]
name=Español
author=……

[strings]
1=LTE Guard
2=Vigilando: {0}  {1}
3=● Correcto
```

`{0}` y `{1}` son marcadores de posición que rellena el programa.

## Archivo de configuración

`~/Library/Application Support/LTE Guard/lte-guard.conf` (lo mantiene la app automáticamente, pero también puedes editarlo a mano; las configuraciones antiguas de un solo objetivo se actualizan solas):

```sh
# un objetivo a curar por línea, campos separados por tabuladores: interfaz, nombre del servicio, USB_VID, USB_PID
TARGETS='en2	My LTE	2c7c	0125'
PRE_CMD=''             # se ejecuta en cuanto se detecta el corte (la red está caída en ese instante: no cuentes con ella)
POST_CMD=''            # se ejecuta tras la recuperación, p. ej. reiniciar un proxy
```

**Ambos enganches admiten varios comandos**: uno por línea, ejecutados en orden. `PRE_CMD` se dispara **en el mismo instante** de la detección: pon ahí la apertura del panel de Red y aparecerá justo a tiempo para ver la reparación entera.

El diálogo ofrece casillas en dos grupos: marcar una escribe al momento en el cuadro de texto correspondiente, y desmarcarla lo quita:

**Habituales** (siempre disponibles)

- Abrir Ajustes del Sistema → Red (va al cuadro del corte) — mira con tus propios ojos cómo vuelve la conexión caída
- Reproducir un sonido
- Enviar una notificación por webhook (sustituye la URL de ejemplo por la tuya; útil en máquinas desatendidas)

La notificación de recuperación y la comprobación de Internet vienen **integradas**, no hay nada que marcar: tras la reparación, la app prueba Internet a través de ese mismo adaptador y solo notifica cuando funciona de verdad (con los segundos empleados). Interfaz activa pero sin Internet muestra `⚠︎`; fallo muestra `✕` — solo en el icono, sin dar la lata.

Por ejemplo, abrir el panel de Red al detectar el corte y, tras la recuperación, reiniciar un proxy y reproducir un sonido:

```sh
PRE_CMD='open "x-apple.systempreferences:com.apple.Network-Settings.extension"'
POST_CMD='launchctl kickstart -k gui/$(id -u)/com.user.gost-lte\nafplay /System/Library/Sounds/Glass.aiff'
```

En el archivo de configuración, los saltos de línea se escriben como `\n` y las comillas simples como `\'` (la app hace el escapado automáticamente; sigue la misma forma si editas a mano).

## Cómo funciona

```
Despertar del sistema (IORegisterForSystemPower + NSWorkspace, doble seguro)
      ↓  ejecutar PRE_CMD de inmediato (p. ej. abrir el panel de Red); esperar 1 s a que el USB tenga corriente
USBDeviceReEnumerate      → si no es USB, networksetup reinicia el servicio
      ↓  sin comprobaciones previas: quien instala esto ya es víctima del dispositivo zombi
sondeo cada segundo: solo cuenta como recuperado cuando la puerta de enlace responde al ping (una IP zombi no engaña al ping)
      ↓  recuperado
ejecutar POST_CMD → probar Internet a través de ese adaptador → notificar solo si funciona de verdad (con el tiempo empleado)
      ↓
el icono lo cuenta todo: giro = reparando, ✓8s = listo, ⚠︎ = sin Internet, ✕ = fallo
```

Varios adaptadores se reparan por separado y en paralelo. El enfriamiento de 15 segundos sirve únicamente para absorber las señales de despertar duplicadas de los dos oyentes.

## Compatibilidad y estado de las pruebas

### Verificado en la práctica

| Elemento | Entorno |
|---|---|
| Modelo | MacBook (Apple Silicon, arm64) |
| Sistema | macOS 26 (Darwin 25.x) |
| Adaptador | Quectel EC25 (VID `2c7c` / PID `0125`), que en modo ECM/NCM aparece como `enX` |
| Escenario | Suspensión al cerrar la tapa → tras despertar la interfaz existe pero no se alcanza la puerta de enlace → tras el desenchufado por software **se recupera en unos 8 segundos**, reproducible muchas veces seguidas |
| Extra | Reinicio automático tras la recuperación del proceso de proxy enlazado a ese adaptador (`POST_CMD`) |

### Debería funcionar por principio, pero falta confirmación real

| Escenario | Previsión y ajustes que podrían hacer falta |
|---|---|
| **Mac con Intel** | En algunos modelos Intel `USBDeviceReEnumerate` necesita root y en el registro aparece `open failed … try sudo`. Solución: ejecútalo una vez con `sudo` para comprobarlo, o cambia al método de «reiniciar el servicio de red» (basta con dejar `USB_VID` vacío en la configuración) |
| **macOS 13 / 14 / 15** | Las API utilizadas (notificaciones de energía de IOKit, `USBDeviceReEnumerate`, `NSStatusItem.isVisible`) son interfaces estables desde la 13, así que se espera un funcionamiento normal. Por debajo de la 13 no arranca (está limitado en el Info.plist) |
| **Adaptadores USB a Ethernet** (AX88179, RTL8153, CM3xx, etc.) | El principio es el mismo, debería funcionar. Ojo: en algunos adaptadores el nombre de la interfaz cambia tras la reenumeración (`en5`→`en6`); en ese caso basta con volver a «Elegir objetivo a curar» desde el menú |
| **Módulos 4G de marcación** (no ECM/NCM, con PPP/AT) | Tras la reenumeración hay que volver a marcar para obtener IP; si no, tras esperar 60 segundos se dará por fallido. Solución: pon tu comando de marcación/reconexión en «Comando tras la recuperación» |
| **Adaptadores de red dentro de un dock** | Si lo que se reenumera es el dispositivo USB del dock entero, se restablecerán también los demás dispositivos conectados (discos externos, cámaras). Si tienes un disco escribiendo en el dock, es mejor usar el método de «reiniciar el servicio de red» |
| **Dispositivos compuestos** (red + lector de tarjetas + puerto serie en uno) | Igual que arriba: el restablecimiento afecta a las demás funciones del mismo dispositivo USB |
| **Compartir Internet por USB del iPhone** | Es un dispositivo NCM de la propia Apple y normalmente el sistema lo recupera solo; si te ocurre lo mismo, esta herramienta también es aplicable por principio |
| **Wi-Fi, Ethernet Thunderbolt y otras interfaces no USB** | Recurre automáticamente a «reiniciar el servicio de red». Resuelve el cuelgue a nivel de software, pero no un bloqueo a nivel de controlador |

Si tu dispositivo no está en la tabla, **abre un Issue y cuéntame el resultado** (modelo, `USB VID:PID`, fragmento de `~/Library/Application Support/LTE Guard/lte-guard.log`), tanto si funciona como si no: es ahora mismo la aportación más necesaria.

## Por qué no se implementa «mantener la conexión durante la suspensión»

Las primeras versiones tenían ese interruptor y se eliminó al comprobar que no funcionaba. Vale la pena dejar escritos los motivos, para que nadie más tropiece:

- **`caffeinate -i -s` no impide la suspensión al cerrar la tapa**. El `man caffeinate` dice claramente que la aserción de `-s` *«is valid only when system is running on AC power»*, y además lo que bloquea es la **suspensión por inactividad**; **cerrar la tapa (Clamshell Sleep) es otra ruta de activación independiente** que no se detiene ni con el cargador enchufado (salvo que un monitor externo active el modo clamshell). En los registros reales, caffeinate estaba corriendo todo el rato y el sistema registraba igualmente `Entering Sleep state due to 'Clamshell Sleep'`.
- **Lo único que sí lo detiene es `sudo pmset -a disablesleep 1`** (el método de herramientas como Amphetamine o InsomniaX), pero eso exige privilegios de root; y además, no dormir con la tapa cerrada significa que la CPU sigue trabajando: **un portátil cerrado y metido en la mochila sin dormir se calienta de verdad**.
- Tras sopesarlo: esta herramienta se centra en hacer bien una sola cosa, «autorreparación en 8 segundos al despertar», y no amplía la superficie de ataque por un caso de uso minoritario que requiere elevación de privilegios y conlleva riesgo para el hardware.

**¿De verdad necesitas mantener la conexión con la tapa cerrada** (descargas largas, emisiones desatendidas, sesiones remotas vivas)? La recomendación es combinarla con [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) (gratuita y en la App Store): ella se encarga de que la máquina no duerma y esta herramienta de repararlo si aun así se corta. Cada una a lo suyo.

## Limitaciones conocidas

- **Cortar de verdad la alimentación USB no es posible** — en Apple Silicon el VBUS lo controla el firmware del SMC y no hay API pública. Para un corte físico de corriente hace falta un hub USB externo compatible con PPPS junto con [uhubctl](https://github.com/mvp/uhubctl).
- En **Macs con Intel**, `USBDeviceReEnumerate` a veces requiere permisos de root y el registro muestra `try sudo`.
- Los **módems de marcación** (no ECM/NCM) pueden necesitar volver a marcar tras la reenumeración; añádelo con `POST_CMD`.
- La app no está notarizada por Apple, así que la primera vez hay que abrirla con clic derecho → Abrir.

## Desinstalación

```bash
launchctl bootout gui/$(id -u)/com.oceantang.lteguard
rm -f ~/Library/LaunchAgents/com.oceantang.lteguard.plist
rm -rf /Applications/LTEGuard.app ~/Library/"Application Support"/"LTE Guard"
```

## Apoyar el proyecto

Si esta pequeña herramienta te ha ahorrado la lata de estar enchufando y desenchufando el USB:

- ⭐ Dale una estrella al repositorio o recomiéndaselo a quien sufra el mismo problema
- 🐛 Abre un Issue con el modelo de tu dispositivo y el registro, para cubrir más adaptadores
- 🌍 Aporta la traducción a un idioma ([CONTRIBUTING.md](CONTRIBUTING.md); basta con cambiar unas líneas de un INI)
- ☕ Invita a un café al autor

Más detalles en [Apoyar el proyecto](SPONSOR.md).

## Comunidad y contacto

- 💬 Dudas de uso e intercambio de ideas: [Discussions](../../discussions)
- 🐛 Errores y sugerencias de funciones: [Issues](../../issues)

### Sobre el autor

**Tang Haiyang (Ocean Tang)**, abogado en ejercicio del bufete Beijing Dongyuan (Shenzhen), en el sector desde 2011 y colegiado desde 2012.

- **Áreas de práctica**: litigios y arbitrajes mercantiles, defensa penal y representación de víctimas en causas penales, conflictos laborales, asesoría jurídica permanente a empresas y due diligence
- **Experiencia**: más de 500 asuntos contenciosos y no contenciosos, y asesoría permanente para varias organizaciones

**Por qué un abogado escribe una app**: obtuve el CCNA en 2002 y el CIW Security Analyst en 2003, y me licencié en 2005 por la Universidad Tecnológica de Wuhan. Siempre me he escrito mis propias herramientas de gestión de casos con VBA + Excel (seguimiento de asuntos, generación de escritos con formato, extracción por OCR, correos automáticos). El origen de esta app también es muy concreto: convertí el enlace de vídeo de un DJI de primera generación en un enlace LTE para usarlo como módem 4G y resultó que cada vez que cerraba y abría la tapa tenía que desenchufarlo y volverlo a enchufar para seguir conectado. Me hartó tanto que me puse a escribir esta app junto con Claude.

Si quieres hablar de temas jurídicos o técnicos, pásate por [Discussions](../../discussions) o abre un Issue.

## Licencia

MIT License
