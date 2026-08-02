# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>¿Tu adaptador de red USB deja de funcionar tras la suspensión del Mac? Se repara solo al despertar.</b><br>
  <sub>Vigilante de adaptadores de red USB en la barra de menús · Swift nativo · sin dependencias · MIT</sub>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.ru.md">Русский</a> · <a href="README.rw.md">Ikinyarwanda</a>
</p>

---

## El problema

Muchos módems LTE USB y adaptadores Ethernet USB se «cuelgan» después de suspender el Mac con la tapa cerrada: el LED sigue encendido, la interfaz continúa en el sistema, pero no pasa tráfico. **Solo se recupera desconectando y volviendo a conectar el adaptador.**

El motivo: macOS no corta la alimentación USB durante la suspensión (el VBUS lo gestiona directamente el firmware SMC, sin API pública), mientras que la sesión USB del dispositivo ya está muerta. Reiniciar el servicio de red no sirve: lo que hay que reiniciar es la capa USB.

## ¿Has llegado buscando?

Todas estas formas de decirlo describen el mismo problema:

> adaptador ethernet USB no funciona después de suspender Mac · MacBook pierde red tras suspensión · adaptador USB-C ethernet no despierta · puerto de red del dock no detectado al despertar · módem 4G se desconecta tras suspender macOS

Los foros oficiales de Apple y MacRumors acumulan años de informes idénticos, tanto en Mac Intel como Apple Silicon. Los consejos habituales (restablecer SMC/NVRAM) ni siquiera existen en Apple Silicon y no atacan la causa. **Lo único que funciona es desconectar y reconectar — justo lo que esta herramienta automatiza.**

## La solución

LTE Guard vive en la barra de menús y escucha los eventos de despertar. Al despertar comprueba el adaptador elegido: si la puerta de enlace no responde, realiza mediante IOKit una **reconexión por software (USBDeviceReEnumerate)**, equivalente a desconectarlo a mano. La conexión suele volver **en unos 8 segundos**.

- 🎯 **Independiente de la marca** — detecta VID/PID al seleccionar, sin lista de dispositivos
- 🔌 **También para adaptadores no USB** — recurre automáticamente a reiniciar el servicio de red
- 🛠 **Comando tras la recuperación** — reiniciar un proxy, volver a marcar…
- 🌍 **62 idiomas** — sigue el idioma del sistema y se puede cambiar desde el menú
- 🪶 **Sin dependencias** — una sola app, sin demonios ni Homebrew

## Instalación

Descarga el `.dmg` desde [Releases](../../releases) y arrástralo a Aplicaciones.

Si macOS dice que no puede verificar al desarrollador (normal en apps sin firmar): **clic derecho en la app → Abrir → Abrir**, o en el Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

## Uso

1. Aparece un icono en la barra de menús
2. Menú → **Elegir objetivo…** → selecciona tu adaptador (los marcados con `· USB` admiten la reconexión por software)
3. Listo: a partir de ahora, si se cae tras cerrar la tapa, se arregla solo

Si algo falla, usa **Ejecutar diagnóstico** en el menú.

---

## Sobre el autor

**Ocean Tang (唐海洋)** — abogado en Shenzhen, China (en la profesión desde 2011, colegiado desde 2012). Litigio mercantil y arbitraje, defensa penal, derecho laboral y asesoría jurídica continuada; más de 500 asuntos.

CCNA en 2002, CIW Security Analyst en 2003, y años escribiendo sus propias herramientas de gestión de expedientes en VBA + Excel. Esta app tiene un origen igual de concreto: convirtió un transmisor de vídeo DJI de primera generación en enlace LTE y lo usaba como módem 4G — pero tras cada cierre de tapa había que desconectar y volver a conectar el adaptador para recuperar la red. Harto, la escribió junto con Claude.

Documentación completa (matriz de compatibilidad, archivo de configuración, contribuir traducciones): [English README](README.en.md).

## License

MIT License
