# Red 5G de laboratorio con OCUDU + Open5GS + srsUE (rama `ocudu`)

> Este documento explica, en lenguaje sencillo, cómo se montó una red 5G completa dentro de un solo computador, cómo se enciende, cómo se prueba y qué resultados dio. Cada comando viene con su explicación, para poder repetirlo y entenderlo.
>
> Los textos marcados con **[REVISAR]** son partes que no quedaron registradas con exactitud durante el trabajo y deben confirmarse antes de publicar (hay una lista al final).

---

## Contenido

1. [¿Qué es este proyecto?](#1-qué-es-este-proyecto)
2. [Qué se ha logrado hasta ahora](#2-qué-se-ha-logrado-hasta-ahora)
3. [Cómo encajan las piezas](#3-cómo-encajan-las-piezas)
4. [Requisitos](#4-requisitos)
5. [Datos que deben coincidir en todas las piezas](#5-datos-que-deben-coincidir-en-todas-las-piezas)
6. [Preparar el entorno (se hace una sola vez)](#6-preparar-el-entorno-se-hace-una-sola-vez)
7. [Compilar los programas (se hace una sola vez)](#7-compilar-los-programas-se-hace-una-sola-vez)
8. [Archivos de configuración](#8-archivos-de-configuración)
9. [Levantar la red (cada vez que se enciende)](#9-levantar-la-red-cada-vez-que-se-enciende)
10. [Hacer las pruebas](#10-hacer-las-pruebas)
11. [Cómo leer las tablas de la consola](#11-cómo-leer-las-tablas-de-la-consola)
12. [Resultados obtenidos](#12-resultados-obtenidos)
13. [Problemas frecuentes y cómo se resolvieron](#13-problemas-frecuentes-y-cómo-se-resolvieron)
14. [Apagar todo](#14-apagar-todo)
15. [Organización del repositorio y ramas (Git)](#15-organización-del-repositorio-y-ramas-git)
16. [Pendientes](#16-pendientes)
17. [Glosario](#17-glosario)
18. [Puntos a revisar antes de publicar](#18-puntos-a-revisar-antes-de-publicar)

---

## 1. ¿Qué es este proyecto?

Una red de telefonía móvil 5G tiene tres partes principales:

- **El teléfono** (en este proyecto, un teléfono simulado por software).
- **La antena** (la estación base, que habla por radio con el teléfono).
- **El núcleo de la red** (el "cerebro": comprueba quién eres, te da una dirección de Internet y te conecta con el resto del mundo).

Aquí las tres partes corren **dentro del mismo computador**, y en lugar de una antena real se usa un **radio virtual** (ZMQ): los programas se pasan las señales por una conexión interna, como dos personas que se hablan por un tubo en vez de por el aire. Así se puede probar todo sin equipo de radio y sin emitir nada por el espectro.

| Pieza | Programa | Para qué sirve (en una frase) |
| --- | --- | --- |
| Núcleo de la red (core) | **Open5GS** | Autentica al teléfono y le da acceso a Internet |
| Antena (gNB) | **OCUDU** | Habla por "radio" con el teléfono y lo conecta al core |
| Teléfono (UE) | **srsUE** (de srsRAN 4G) | Teléfono simulado con una SIM virtual |
| Base de datos | **MongoDB** | Guarda las SIM autorizadas del core |
| Medición | **iperf3, ping, top** | Miden velocidad, retardo y consumo de CPU |

**¿Qué es OCUDU?** Es la continuación del proyecto *srsRAN Project*; el código es el mismo, y pasó a llamarse OCUDU. Por eso muchos tutoriales viejos hablan de "srsRAN" y aquí se usa "OCUDU".

**Fases del proyecto**

| Fase | Qué es | Estado |
| --- | --- | --- |
| 1 | Diseño y planeación en papel | Hecha (documento aparte) |
| 2 | Todo simulado en un computador (sin radio real) | **Hecha: esto es lo que describe este README** |
| 3 | Radio real (USRP) y teléfono comercial con SIM propia | Pendiente |

---

## 2. Qué se ha logrado hasta ahora

- El core Open5GS funciona: 17 servicios más el panel web, todos activos.
- Se compilaron OCUDU (el gNB) y srsUE (el teléfono simulado).
- El teléfono simulado **se registra en la red, abre una sesión de datos y recibe una dirección IP** (10.45.0.x).
- Hay tráfico real en ambos sentidos, con 0 % de pérdida de paquetes.
- Se midió velocidad, retardo, uso de CPU y el comportamiento del gNB (qué "calidad de modulación" elige según la señal).
- Se capturó el tráfico entre las piezas para analizarlo con Wireshark.

Resultados resumidos (detalle en la sección 12):

| Medida | Resultado |
| --- | --- |
| Retardo en reposo (ida y vuelta) | 29 a 30 ms |
| Velocidad de bajada | 26,4 Mb/s |
| Velocidad de subida | 5,8 Mb/s |
| Retardo máximo cuando la red está llena | 0,9 s (bajada) |

---

## 3. Cómo encajan las piezas

```
  TELÉFONO SIMULADO            ANTENA                     NÚCLEO DE LA RED (Open5GS)
  ┌────────────┐   radio     ┌─────────┐  N2 (control)   ┌─────┐
  │  srsUE     │ ─virtual──► │  gNB    │ ──────────────► │ AMF │ 127.0.0.5:38412
  │ (en ue1)   │   (ZMQ)     │ OCUDU   │                 └─────┘
  └────────────┘             │         │  N3 (datos)     ┌─────┐   ┌──────────┐
   tun_srsue                 │         │ ──────────────► │ UPF │──►│ Internet │
   IP 10.45.0.x              └─────────┘  127.0.0.100    └─────┘   └──────────┘
                                          ↔ 127.0.0.7     ogstun (10.45.0.1)
```

**Las "interfaces"** son los cables lógicos entre las piezas:

| Nombre | Entre quién y quién | Para qué sirve |
| --- | --- | --- |
| Radio virtual (ZMQ) | srsUE ↔ gNB | Intercambian las señales de radio como datos |
| N1 | teléfono ↔ AMF | Mensajes de registro y autenticación (viajan "por dentro" del gNB) |
| N2 | gNB ↔ AMF | Control: "hay un teléfono que quiere conectarse" |
| N3 | gNB ↔ UPF | Los datos del usuario (el tráfico de Internet) |
| N4 | SMF ↔ UPF | El core organiza cómo se reparte el tráfico |

**Direcciones y puertos usados**

| Qué | Valor |
| --- | --- |
| Dirección del AMF (para el gNB) | 127.0.0.5, puerto 38412 |
| Dirección del gNB | 127.0.0.100 |
| Dirección del UPF para datos (N3) | 127.0.0.7, puerto 2152 |
| Red de los teléfonos | 10.45.0.0/16 (la puerta de salida es 10.45.0.1) |
| Puertos del radio virtual | gNB: envía por 2000 y recibe por 2001; UE: envía por 2001 y recibe por 2000 (**cruzados**: lo que uno envía, el otro lo recibe) |
| Panel web de Open5GS | http://localhost:9999 (usuario `admin`, contraseña `1423`) |

**Ventanas de terminal.** Para trabajar cómodo se usan cuatro ventanas, y en este README las llamamos así:

| Ventana | Para qué |
| --- | --- |
| **A** | El gNB (se queda ocupada mostrando mensajes) |
| **B** | El teléfono simulado (srsUE) |
| **C** | Comandos de prueba y mediciones |
| **D** | El servidor de iperf3 (se queda abierto) |

---

## 4. Requisitos

| Qué | Con qué se hizo |
| --- | --- |
| Computador | Intel Core i5-12450H, 12 hilos, 6,9 GiB de RAM |
| Sistema | Ubuntu 26.04.1 LTS |
| Espacio libre | Unos 10 GB para compilar y guardar capturas |
| Internet | Para descargar paquetes y código |

**Importante sobre la memoria.** Con poca memoria libre los resultados empeoran: con 655 MiB disponibles la bajada dio 23,1 Mb/s; con 2,8 GiB o más dio 26,4 Mb/s. Cierren navegadores y programas pesados antes de medir. Para ver cuánta hay: `free -h` (mire la columna `available`).

---

## 5. Datos que deben coincidir en todas las piezas

Estos valores tienen que ser **idénticos** en el core, en el gNB y en la SIM del teléfono. Si uno no coincide, el teléfono no se conecta.

| Parámetro | Valor | Qué es |
| --- | --- | --- |
| PLMN (MCC / MNC) | 001 / 01 | "Código de país y operador"; 001/01 es el de pruebas |
| TAC | 7 | Código del área de la antena |
| Slice (SST) | 1, sin SD | Tipo de servicio de red (el básico) |
| DNN | `internet` | Nombre de la "puerta" de datos |
| IMSI | 001010123456780 | Número de identificación de la SIM |
| K | 00112233445566778899aabbccddeeff | Clave secreta de la SIM (de pruebas) |
| OPc | 63bfa50ee6523365ff14c1f45f88737d | Segunda clave de la SIM (de pruebas) |
| Red de los teléfonos | 10.45.0.0/16 | Direcciones que se reparten |
| Banda / canal / ancho | n3 / 368500 / 10 MHz | Frecuencia que usa la celda (virtual) |
| Separación de subportadoras | 15 kHz | Parámetro de la modulación |

> **Seguridad.** Las claves K y OPc de arriba son valores de práctica. Cuando pasen a una SIM real (Fase 3), **no las publiquen en el repositorio**. Y cambien la contraseña `1423` del panel web de Open5GS.

---

## 6. Preparar el entorno (se hace una sola vez)

### 6.1 MongoDB (la base de datos del core)

**[REVISAR]** Los comandos con los que se instaló MongoDB 8.0 no quedaron anotados. Completen aquí los que usaron.

**Problema conocido de Ubuntu 26.04.** El kernel de este Ubuntu es muy nuevo y MongoDB 8.0 se niega a arrancar. La solución (no oficial, sirve para laboratorio) es decirle a MongoDB que use una opción de compatibilidad:

```bash
sudo mkdir -p /etc/systemd/system/mongod.service.d
printf '[Service]\nEnvironment="GLIBC_TUNABLES=glibc.pthread.rseq=1"\n' | sudo tee /etc/systemd/system/mongod.service.d/rseq.conf
sudo systemctl daemon-reload && sudo systemctl restart mongod
```

| Parte | Qué hace |
| --- | --- |
| `sudo` | Ejecuta el comando con permisos de administrador |
| `mkdir -p /etc/systemd/system/mongod.service.d` | Crea una carpeta de "ajustes extra" para el servicio `mongod`. `-p` evita error si ya existe |
| `printf '[Service]\nEnvironment="..."\n'` | Escribe un texto de dos líneas: una sección `[Service]` y una variable de entorno. `\n` es un salto de línea |
| `GLIBC_TUNABLES=glibc.pthread.rseq=1` | La variable de compatibilidad que evita el error con el kernel nuevo |
| `\| sudo tee /etc/systemd/system/mongod.service.d/rseq.conf` | Guarda ese texto en el archivo `rseq.conf`. Se usa `tee` porque `sudo` no aplica a una redirección `>` normal |
| `sudo systemctl daemon-reload` | Le dice a Linux que vuelva a leer los archivos de servicios |
| `sudo systemctl restart mongod` | Reinicia MongoDB con el ajuste nuevo |

Comprobar que funciona:

```bash
systemctl status mongod
```

Debe decir `active (running)`. (`systemctl status` muestra el estado de un servicio.)

### 6.2 Open5GS (el core)

```bash
sudo add-apt-repository ppa:open5gs/latest
sudo apt install -y open5gs
```

| Parte | Qué hace |
| --- | --- |
| `add-apt-repository ppa:open5gs/latest` | Agrega el almacén oficial de paquetes de Open5GS (un PPA). Sí soporta Ubuntu 26.04 |
| `apt install -y open5gs` | Instala Open5GS. `-y` responde "sí" a todas las preguntas. Se instalaron 17 servicios (versión 2.8.0) |

Open5GS queda guardado en `/etc/open5gs/` (los archivos `.yaml` de cada pieza) y sus servicios arrancan solos con el computador.

Comprobar los servicios:

```bash
systemctl list-units 'open5gs-*' --no-pager
```

| Parte | Qué hace |
| --- | --- |
| `systemctl list-units 'open5gs-*'` | Lista todos los servicios cuyo nombre empieza por `open5gs-` |
| `--no-pager` | Muestra todo de una vez, sin pantalla paginada |

### 6.3 Poner el código de país/operador y el área (PLMN y TAC)

Open5GS viene con valores de ejemplo (999/70). Hay que cambiarlos a 001/01 y TAC 7:

```bash
sudo sed -i 's/mcc: 999/mcc: 001/; s/mnc: 70/mnc: 01/' /etc/open5gs/nrf.yaml /etc/open5gs/amf.yaml
sudo sed -i 's/tac: 1$/tac: 7/' /etc/open5gs/amf.yaml
sudo systemctl restart open5gs-nrfd open5gs-amfd
```

| Parte | Qué hace |
| --- | --- |
| `sed -i 's/A/B/'` | Busca el texto `A` y lo cambia por `B` **dentro del archivo** (`-i` = editar en el sitio) |
| `s/mcc: 999/mcc: 001/; s/mnc: 70/mnc: 01/` | Dos cambios en una sola pasada, separados por `;` |
| `/etc/open5gs/nrf.yaml /etc/open5gs/amf.yaml` | Los dos archivos que se modifican |
| `s/tac: 1$/tac: 7/` | `$` significa "al final de la línea": solo cambia las líneas que terminan en `tac: 1` |
| `systemctl restart open5gs-nrfd open5gs-amfd` | Reinicia los dos servicios (NRF y AMF) para que lean los valores nuevos |

Comprobar:

```bash
grep -nE 'mcc|mnc|tac' /etc/open5gs/amf.yaml /etc/open5gs/nrf.yaml
```

`grep -nE` busca líneas con alguna de esas palabras (`-n` muestra el número de línea, `-E` permite el "o" con `|`). Deben aparecer 001, 01 y 7.

### 6.4 Que los teléfonos puedan salir a Internet (NAT y reenvío)

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-open5gs.conf
sudo apt install -y iptables-persistent && sudo netfilter-persistent save
```

| Parte | Qué hace |
| --- | --- |
| `sysctl -w net.ipv4.ip_forward=1` | Activa que el computador reenvíe paquetes de una red a otra, como un router. `-w` escribe el valor |
| `iptables -t nat -A POSTROUTING ... -j MASQUERADE` | Regla de NAT: los paquetes de la red 10.45.0.0/16 que salen por cualquier interfaz que **no** sea `ogstun` se disfrazan con la dirección del computador, para que Internet sepa responderles |
| `-s 10.45.0.0/16` | "Origen: la red de los teléfonos" |
| `! -o ogstun` | "Salida: cualquier interfaz menos `ogstun`" (el `!` niega) |
| `echo ... \| sudo tee /etc/sysctl.d/99-open5gs.conf` | Guarda el ajuste del reenvío para que sobreviva a un reinicio |
| `apt install -y iptables-persistent` | Programa que guarda las reglas del cortafuegos |
| `netfilter-persistent save` | Guarda las reglas actuales para que se carguen al encender |

### 6.5 Abrir el cortafuegos para la interfaz del core (¡muy importante!)

En este computador el cortafuegos bloquea por defecto casi todo lo que entra. Sin estas reglas, **el teléfono se conecta pero el ping no funciona**:

```bash
sudo iptables -I INPUT -i ogstun -j ACCEPT
sudo iptables -I FORWARD -i ogstun -j ACCEPT
sudo iptables -I FORWARD -o ogstun -j ACCEPT
```

| Parte | Qué hace |
| --- | --- |
| `iptables -I INPUT -i ogstun -j ACCEPT` | "Acepta lo que entra al computador por la interfaz `ogstun`". `-I` pone la regla al **inicio** de la lista (para que gane a las que bloquean) |
| `iptables -I FORWARD -i ogstun -j ACCEPT` | "Acepta el tráfico que pasa de largo y entra por `ogstun`" |
| `iptables -I FORWARD -o ogstun -j ACCEPT` | "Acepta el tráfico que pasa de largo y sale por `ogstun`" |

Estas reglas **se pierden al reiniciar**. Para guardarlas (no se ha hecho todavía):

```bash
sudo netfilter-persistent save
```

Ver las reglas que hay: `sudo iptables -S INPUT | grep ogstun`.

### 6.6 Panel web para registrar la SIM

```bash
# Node.js 20 (NodeSource) y panel web de Open5GS
# [REVISAR] confirmar que estos son los comandos usados:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
curl -fsSL https://open5gs.org/open5gs/assets/webui/install | sudo -E bash -
```

Se abre en el navegador: `http://localhost:9999` (usuario `admin`, contraseña `1423`).

**Registrar la SIM del teléfono** (menú *Subscribers* → botón "+"):

| Campo | Valor |
| --- | --- |
| IMSI | 001010123456780 |
| K | 00112233445566778899aabbccddeeff |
| OPc | 63bfa50ee6523365ff14c1f45f88737d |
| Slice | SST = 1, sin SD |
| Sesión (DNN/APN) | `internet`, tipo IPv4, calidad 5QI = 9 |
| UE IPv4 / SMF IPv4 | Vacíos (la red las asigna) |

### 6.7 El "teléfono" necesita su propio espacio de red

El teléfono simulado vive en un **namespace** (una "habitación" de red aparte) llamado `ue1`. Así su tráfico tiene que pasar de verdad por el gNB y el core en vez de tomar un atajo dentro del computador.

```bash
sudo ip netns add ue1 2>/dev/null; ip netns list
```

| Parte | Qué hace |
| --- | --- |
| `ip netns add ue1` | Crea el espacio de red `ue1` |
| `2>/dev/null` | Si falla porque ya existe, no muestra el error |
| `ip netns list` | Lista los espacios de red existentes: debe aparecer `ue1` |

---

## 7. Compilar los programas (se hace una sola vez)

**Compilar** es convertir el código fuente (texto) en un programa que se puede ejecutar. Tarda un buen rato.

### 7.1 OCUDU (el gNB): unos 33 minutos

```bash
sudo apt install -y cmake make gcc g++ pkg-config libfftw3-dev libmbedtls-dev libsctp-dev libyaml-cpp-dev libgtest-dev libzmq3-dev
git clone --branch release_26_04 --depth 1 https://gitlab.com/ocudu/ocudu.git
cd ocudu && mkdir build && cd build
cmake ../ -DENABLE_EXPORT=ON -DENABLE_ZEROMQ=ON
make -j2 gnb
```

| Parte | Qué hace |
| --- | --- |
| `apt install ... cmake make gcc g++ ...` | Instala las herramientas de compilación y las bibliotecas que el gNB necesita (matemática, seguridad, red, y **ZeroMQ** para el radio virtual) |
| `git clone --branch release_26_04 --depth 1 <url>` | Descarga el código, solo la versión etiquetada `release_26_04` (`--depth 1` evita bajar todo el historial) |
| `mkdir build && cd build` | Crea una carpeta de trabajo para los archivos de compilación y entra en ella |
| `cmake ../ -DENABLE_ZEROMQ=ON` | "Prepara" la compilación y **activa el radio virtual**. Debe decir `Found libZEROMQ` y `Building OCUDU version 26.04.0` |
| `-DENABLE_EXPORT=ON` | Opción adicional de la documentación |
| `make -j2 gnb` | Compila solo el programa `gnb`. `-j2` usa 2 procesos a la vez (con más, un computador de poca memoria se ahoga) |

Resultado: el programa queda en `~/ocudu/build/apps/gnb/gnb` (unos 52 MB).

### 7.2 srsUE (el teléfono simulado): unos 6 minutos

```bash
sudo apt install -y build-essential cmake libfftw3-dev libmbedtls-dev libboost-program-options-dev libconfig++-dev libsctp-dev libzmq3-dev
cd ~ && git clone https://github.com/srsRAN/srsRAN_4G.git
cd srsRAN_4G && mkdir build && cd build
cmake ../ && make -j2 srsue
```

Mismos conceptos que arriba. El programa queda en `~/srsRAN_4G/build/srsue/src/srsue`. El `cmake` debe confirmar que encontró ZeroMQ.

---

## 8. Archivos de configuración

Estos dos archivos viven en `~/ocudu-lab/` y deben copiarse al repositorio (carpeta `config/`):

### 8.1 `gnb_zmq.yml` (la antena)

Se partió del ejemplo de la documentación de OCUDU (tutorial de srsUE con ZMQ) y se cambió:

| Parámetro | Valor | Por qué |
| --- | --- | --- |
| Dirección del AMF (`addr`) | 127.0.0.5 | Open5GS instalado en el mismo equipo escucha ahí (el ejemplo traía 10.53.1.2) |
| Dirección local del gNB (`bind_addr`) | 127.0.0.100 | La dirección desde la que el gNB habla con el core (el ejemplo traía 10.53.1.1) |
| Líneas de PRACH (`total_nof_ra_preambles`, `nof_ssb_per_ro`, `nof_cb_preambles_per_ssb`) | **Eliminadas** | Provocaban el error `Invalid nof. SSB per RACH occasion value 0.25` |
| `ngap_enable` | `true` | Guarda una captura de los mensajes N2 (para Wireshark) |
| `all_level` (nivel de registro) | `warning` | Registra solo lo importante; antes el registro llegaba a 126 MB |
| PLMN | "00101" | Igual que el core |
| TAC | 7 | Igual que el core |
| Slice SST | 1 | Igual que el core |
| Banda / canal / ancho | 3 / 368500 / 10 MHz | Celda virtual de pruebas |
| Radio | ZMQ, 11,52 millones de muestras por segundo, ganancias en 0 | Radio virtual |
| Tabla de modulación (`mcs_table`) | `qam64` | Hasta 64QAM, lo que entiende srsUE |

### 8.2 `ue_zmq.conf` (el teléfono)

Se usa el de la documentación casi sin cambios. Lo importante que contiene:

| Parámetro | Valor |
| --- | --- |
| IMSI, K, OPc | Los de la sección 5 |
| Radio virtual | ZMQ, puertos cruzados con el gNB |
| Espacio de red (`netns`) | `ue1` |
| Sesión (`apn`) | `internet`, protocolo IPv4 |
| `all_level` | `warning` (se bajó para no llenar el disco) |
| `tx_gain` | 50 (valor original). **Ojo:** durante un experimento se cambió a 30 |

Para volver al valor original:

```bash
sed -i 's/^tx_gain = 30/tx_gain = 50/' ~/ocudu-lab/ue_zmq.conf
grep -n 'tx_gain' ~/ocudu-lab/ue_zmq.conf
```

(`^` significa "al comienzo de la línea"; `grep -n` muestra la línea para confirmar.)

---

## 9. Levantar la red (cada vez que se enciende)

**El orden importa: core → gNB → teléfono.** Si algo falla, apaguen en orden inverso (teléfono primero, gNB después) y vuelvan a empezar.

### Paso 1: comprobar el core (ventana C)

```bash
systemctl is-active mongod open5gs-amfd open5gs-smfd open5gs-upfd open5gs-nrfd
sudo iptables -S INPUT | grep ogstun
free -h | head -n 2
```

| Parte | Qué hace |
| --- | --- |
| `systemctl is-active a b c` | Dice `active` o no para cada servicio. Deben salir todos `active` |
| `iptables -S INPUT \| grep ogstun` | Muestra la regla del cortafuegos de la sección 6.5. Si no sale nada, hay que volver a aplicarla |
| `free -h \| head -n 2` | Memoria libre (`-h` = en unidades legibles; `head -n 2` = solo las dos primeras líneas) |

Si falta la regla del cortafuegos tras un reinicio, aplíquenla otra vez (sección 6.5).

### Paso 2: encender el gNB (ventana A)

```bash
cd ~/ocudu/build/apps/gnb
script -q -f ~/ocudu-lab/evidencia/gnb_consola.txt -c "sudo ./gnb -c ~/ocudu-lab/gnb_zmq.yml"
```

| Parte | Qué hace |
| --- | --- |
| `cd ~/ocudu/build/apps/gnb` | Entra a la carpeta donde está el programa |
| `script -q -f <archivo> -c "<comando>"` | Ejecuta el comando **y guarda en el archivo todo lo que se ve en pantalla**. `-q` = silencioso, `-f` = va escribiendo el archivo mientras tanto, `-c` = el comando a ejecutar |
| `sudo ./gnb -c ~/ocudu-lab/gnb_zmq.yml` | Arranca el gNB con la configuración indicada (`-c`). Necesita `sudo` porque crea interfaces de red |

> `script` **sobrescribe** el archivo si ya existe. Para no perder datos de una prueba anterior, cambien el nombre (por ejemplo `gnb_prueba2.txt`) o copien el archivo antes.

**Qué debe aparecer:**

```
N2: Connection to AMF on 127.0.0.5:38412 completed
==== gNB started ===
```

**Esperen a ver `gNB started` antes de encender el teléfono.**

### Paso 3: (opcional) capturar el tráfico (ventana C)

Hacerlo **antes** de encender el teléfono si quieren ver el registro completo en Wireshark:

```bash
sudo tcpdump -i lo -w ~/ocudu-lab/evidencia/captura_n3_n4.pcap 'udp port 2152 or udp port 8805'
```

| Parte | Qué hace |
| --- | --- |
| `tcpdump -i lo` | Escucha el tráfico de la interfaz interna `lo` (todo ocurre dentro del computador) |
| `-w <archivo>` | Guarda lo capturado en un archivo `.pcap` |
| `'udp port 2152 or udp port 8805'` | Solo captura el puerto 2152 (datos N3) y el 8805 (N4). Sin filtro el archivo sería enorme |

Se detiene con `Ctrl+C`. Estos archivos pesan 130 a 140 MB: **no los suban a Git** (ver sección 15).

### Paso 4: encender el teléfono simulado (ventana B)

```bash
cd ~/srsRAN_4G/build/srsue/src
script -q -f ~/ocudu-lab/evidencia/ue_consola.txt -c "sudo ./srsue ~/ocudu-lab/ue_zmq.conf"
```

Mismo patrón que el gNB. **Debe aparecer:**

```
Random Access Complete.     c-rnti=0x4601
RRC Connected
PDU Session Establishment successful. IP: 10.45.0.x
RRC NR reconfiguration successful.
```

Esas líneas significan, en orden: pidió conexión por radio, la antena lo aceptó, el core le abrió una sesión de datos y le dio la IP `10.45.0.x`. **Esa IP cambia en cada conexión** (10.45.0.2, .3, .4...).

### Paso 5: ruta y ping (ventana C)

```bash
UE_IP=$(sudo ip netns exec ue1 ip -4 -o addr show tun_srsue | awk '{print $4}' | cut -d/ -f1)
echo "IP del UE: $UE_IP"
sudo ip netns exec ue1 ip route add default via 10.45.0.1 dev tun_srsue 2>/dev/null
sudo ip netns exec ue1 ping -c4 10.45.0.1
ping -c4 $UE_IP
```

| Parte | Qué hace |
| --- | --- |
| `UE_IP=$( ... )` | Guarda en una variable la IP actual del teléfono |
| `ip netns exec ue1 <comando>` | Ejecuta el comando **dentro** del espacio de red del teléfono |
| `ip -4 -o addr show tun_srsue` | Muestra la dirección IPv4 (`-4`) de la interfaz del teléfono (`tun_srsue`) en una sola línea (`-o`) |
| `awk '{print $4}'` | Se queda con la 4.ª columna (algo como `10.45.0.4/24`) |
| `cut -d/ -f1` | Corta por la `/` y se queda con la primera parte: `10.45.0.4` |
| `ip route add default via 10.45.0.1 dev tun_srsue` | Le dice al teléfono: "para ir a cualquier lado, sal por `10.45.0.1` (el core)". `2>/dev/null` oculta el aviso si la ruta ya existía |
| `ping -c4 10.45.0.1` (dentro de `ue1`) | Teléfono → core: 4 pings. Debe responder con unos 20 a 40 ms |
| `ping -c4 $UE_IP` (fuera) | Core → teléfono: 4 pings |

Si los dos ping responden, **la red está funcionando**.

### Paso 6: servidor de medición (ventana D)

```bash
iperf3 -s -B 10.45.0.1 -i 1
```

| Parte | Qué hace |
| --- | --- |
| `iperf3 -s` | Arranca iperf3 como **servidor** (espera a que un cliente se conecte para medir) |
| `-B 10.45.0.1` | Escucha solo en la dirección del core |
| `-i 1` | Muestra resultados cada segundo |

Debe decir `Server listening on 5201`. Dejen esta ventana abierta durante todas las pruebas. Si dice `Address already in use`, ya hay un servidor corriendo (ver sección 13).

### Paso 7: activar las tablas de métricas (ventanas A y B)

En la **ventana A** (gNB) escriban `t` y Enter. En la **ventana B** (teléfono) escriban `t` y Enter. Empieza a mostrarse una tabla nueva cada segundo (se explica en la sección 11). Para apagarlas, `t` y Enter otra vez.

> **Error típico:** escribir `t` en la ventana C (aparece `t: command not found`). El `t` solo funciona en las ventanas de los programas A y B.

---

## 10. Hacer las pruebas

Todas se ejecutan en la **ventana C**, con la red levantada y el servidor de iperf3 abierto. Los resultados se guardan en `~/ocudu-lab/evidencia/`:

```bash
cd ~/ocudu-lab/evidencia
```

### 10.1 Función auxiliar `run_test`

Ejecuta una prueba y, al mismo tiempo, mide la CPU. **Se pega una vez por ventana** (se pierde al cerrarla):

```bash
run_test() {
  n="$1"; shift
  top -b -d 1 -n 35 -w 200 | grep -E '%Cpu|gnb|srsue|iperf3|open5gs-upfd' > cpu_$n.txt &
  "$@" | tee $n.txt | tail -n 5
  wait
}
```

| Línea | Qué hace |
| --- | --- |
| `run_test() { ... }` | Define una "función": un comando personalizado llamado `run_test` |
| `n="$1"; shift` | Guarda el primer dato que se le pasa (el nombre de la prueba) en `n` y lo descarta de la lista |
| `top -b -d 1 -n 35 -w 200` | `top` muestra los procesos que más CPU usan. `-b` = modo texto, `-d 1` = cada 1 segundo, `-n 35` = 35 veces, `-w 200` = líneas anchas |
| `\| grep -E '%Cpu\|gnb\|srsue\|iperf3\|open5gs-upfd'` | Se queda solo con las líneas de los procesos que interesan |
| `> cpu_$n.txt &` | Guarda eso en `cpu_<nombre>.txt` y lo deja corriendo **en segundo plano** (`&`) |
| `"$@" \| tee $n.txt \| tail -n 5` | Ejecuta el resto del comando (la prueba), lo guarda en `<nombre>.txt` (`tee`) y muestra solo las últimas 5 líneas |
| `wait` | Espera a que termine la medición de CPU antes de devolver el control |

Uso: `run_test <nombre> <comando de la prueba>`.

### 10.2 Retardo (ping) en reposo

```bash
ping -c 100 -i 0.2 $UE_IP | tee ping_bajada_100.txt | tail -n 3
sudo ip netns exec ue1 ping -c 100 -i 0.2 10.45.0.1 | tee ping_subida_100.txt | tail -n 3
```

| Parte | Qué hace |
| --- | --- |
| `ping -c 100` | Envía 100 pings |
| `-i 0.2` | Uno cada 0,2 segundos |
| `\| tee archivo` | Guarda todo y lo sigue mostrando |
| `\| tail -n 3` | Muestra solo el resumen final (3 últimas líneas) |

La primera línea mide core → teléfono ("bajada"); la segunda, teléfono → core ("subida"). Lo importante del resumen es `rtt min/avg/max/mdev` (mínimo / promedio / máximo / variación, en milisegundos).

### 10.3 Retardo hacia Internet

```bash
ping -c 20 8.8.8.8 | tee ping_host_internet.txt | tail -n 3
sudo ip netns exec ue1 ping -c 20 8.8.8.8 | tee ping_ue_internet.txt | tail -n 3
```

`8.8.8.8` es un servidor de Google. El primero se hace desde el computador **sin pasar por 5G** y el segundo desde el teléfono. La diferencia (unos 32 ms) es lo que añade la red 5G.

### 10.4 Velocidad: TCP y UDP (iperf3)

**TCP** es el tipo de tráfico "de verdad" (páginas web, descargas): se asegura de que todo llegue. **UDP** manda a una velocidad fija y cuenta cuánto se pierde.

```bash
run_test iperf_subida_tcp   sudo ip netns exec ue1 iperf3 -c 10.45.0.1 -i 1 -t 30
run_test iperf_bajada_tcp   sudo ip netns exec ue1 iperf3 -c 10.45.0.1 -i 1 -t 30 -R
run_test iperf_udp_subida_4M   sudo ip netns exec ue1 iperf3 -c 10.45.0.1 -i 1 -t 30 -u -b 4M
run_test iperf_udp_bajada_20M  sudo ip netns exec ue1 iperf3 -c 10.45.0.1 -i 1 -t 30 -u -b 20M -R
```

| Parte | Qué hace |
| --- | --- |
| `iperf3 -c 10.45.0.1` | Cliente: se conecta al servidor del core |
| `-i 1` | Reporta cada segundo |
| `-t 30` | La prueba dura 30 segundos |
| `-R` | **Modo inverso**: ahora el servidor envía y el teléfono recibe (mide la **bajada**). Sin `-R` mide la **subida** |
| `-u` | Usa UDP en lugar de TCP |
| `-b 20M` | Velocidad que se intenta enviar: 20 megabits por segundo |
| `sudo ip netns exec ue1 ...` | Todo se ejecuta como si fuera el teléfono |

Cada prueba dura unos 35 segundos y no se debe interrumpir. El resultado importante está al final: la línea `receiver` es la velocidad realmente recibida.

### 10.5 Barrido de carga (¿hasta dónde aguanta la red?)

Se envía cada vez más tráfico UDP y se ve en qué momento la red empieza a perder datos:

```bash
for b in 25 30 35 40; do
  echo ">>> bajada UDP ${b}M"
  sudo ip netns exec ue1 iperf3 -c 10.45.0.1 -t 10 -u -b ${b}M -R | tee barrido_bajada_${b}M.txt | grep receiver
done
for b in 5 6 8 10; do
  echo ">>> subida UDP ${b}M"
  sudo ip netns exec ue1 iperf3 -c 10.45.0.1 -t 10 -u -b ${b}M | tee barrido_subida_${b}M.txt | grep receiver
done
```

| Parte | Qué hace |
| --- | --- |
| `for b in 25 30 35 40; do ... done` | Repite lo de adentro cuatro veces, con `b` valiendo 25, luego 30, 35 y 40 |
| `${b}M` | Reemplaza `b` por el valor (por ejemplo `30M`) |
| `grep receiver` | De toda la salida, muestra solo la línea del receptor |

**Qué se encontró:** la bajada se satura cerca de **27 Mb/s** y la subida cerca de **6,1 Mb/s**. Por encima de eso, lo que se envía de más no llega.

> Ojo: a 30 Mb/s de bajada el cliente muestra "0 % de pérdida", pero el servidor había enviado más datagramas de los que el cliente contó. Para saber cuánto no llegó de verdad, hay que comparar la línea `sender` del servidor (ventana D) con la del cliente.

### 10.6 Retardo cuando la red está llena

Se hace un ping continuo **mientras** corre la prueba de velocidad:

```bash
sudo ip netns exec ue1 ping -c 35 -i 1 10.45.0.1 > ping_bajo_carga_bajada.txt &
run_test trazas_bajada sudo ip netns exec ue1 iperf3 -c 10.45.0.1 -i 1 -t 30 -R
tail -n 2 ping_bajo_carga_bajada.txt
```

| Parte | Qué hace |
| --- | --- |
| `ping -c 35 -i 1 ... > archivo &` | 35 pings, uno por segundo, guardados en un archivo y en segundo plano |
| `run_test ...` | La prueba de bajada de 30 segundos al mismo tiempo |
| `tail -n 2 archivo` | Muestra el resumen del ping |

Para la subida, se repite quitando `-R` y cambiando el nombre del archivo a `ping_bajo_carga_subida.txt`.

**Qué se encontró:** el retardo sube de 30 ms a unos 450 ms de promedio (máximo 0,9 s) en bajada. Es el efecto "cola llena": como cuando hay mucha gente en una fila, nadie se pierde, pero todos esperan.

### 10.7 ¿Hay cola acumulada en el sistema operativo?

```bash
tc -s qdisc show dev ogstun
sudo ip netns exec ue1 tc -s qdisc show dev tun_srsue
```

`tc -s qdisc show dev <interfaz>` muestra las "filas de espera" de una interfaz con estadísticas. Interesan las líneas `dropped` (paquetes descartados) y `backlog` (paquetes esperando): ambas dieron 0, así que la cola **no** está en Linux, sino dentro del gNB.

### 10.8 Consumo de CPU

Las pruebas con `run_test` ya dejaron archivos `cpu_*.txt`. Para resumirlos:

```bash
for f in cpu_iperf_bajada_tcp.txt cpu_iperf_udp_bajada_20M.txt cpu_iperf_udp_subida_4M.txt; do
  echo "== $f"
  awk '$12 ~ /gnb|srsue|iperf3|open5gs-upfd/ {s[$12]+=$9; n[$12]++; if($9>m[$12]) m[$12]=$9} END{for(k in s) printf "%s: media=%.0f%% max=%.0f%% (n=%d)\n", k, s[k]/n[k], m[k], n[k]}' $f
done
```

| Parte | Qué hace |
| --- | --- |
| `awk '...'` | Un lenguaje para procesar columnas de texto |
| `$12 ~ /gnb\|srsue\|.../` | "Si la columna 12 (el nombre del proceso) es uno de estos..." |
| `s[$12]+=$9; n[$12]++` | "...suma la columna 9 (el % de CPU) y cuenta cuántas veces apareció" |
| `if($9>m[$12]) m[$12]=$9` | Guarda el máximo |
| `END{ ... printf ...}` | Al final, imprime por proceso: promedio, máximo y cantidad de muestras |

El 100 % equivale a **un** núcleo. El gNB usó unos 200 % (dos núcleos) y el UPF menos de 10 %.

### 10.9 Ver qué decide el gNB: MCS, calidad y errores

Con las tablas activadas (paso 7) y una prueba corriendo, los archivos `gnb_consola.txt` y `ue_consola.txt` guardan una fila por segundo. Para extraer solo las filas con tráfico de bajada:

```bash
tr -d '\r' < gnb_consola.txt | awk '$1 ~ /^[0-9]+$/ && $3=="|" && $7 ~ /M$/' | cut -c1-140 | head -n 30
```

| Parte | Qué hace |
| --- | --- |
| `tr -d '\r'` | Quita unos caracteres invisibles que deja `script` |
| `awk '$1 ~ /^[0-9]+$/ && $3=="\|" && $7 ~ /M$/'` | Filas de datos (empiezan con un número, tienen `\|` en la 3.ª columna) cuya 7.ª columna (velocidad) termina en `M` (megabits) |
| `cut -c1-140` | Recorta cada línea a 140 caracteres para que quepa en pantalla |
| `head -n 30` | Muestra las primeras 30 filas |

Para las filas de **subida** se cambia `$7` por `$17`. Para el teléfono:

```bash
tr -d '\r' < ue_consola.txt | grep -aE '^ *nr ' | awk '$10!="0.0" || $16!="0.0"' | cut -c1-140 | head -n 30
```

(`grep -a` trata el archivo como texto aunque tenga caracteres raros; `-E '^ *nr '` toma solo las líneas de datos del teléfono.)

### 10.10 Experimento: bajar la potencia de transmisión del teléfono

Se probó si la subida mejoraba bajando `tx_gain` de 50 a 30:

```bash
grep -n 'tx_gain' ~/ocudu-lab/ue_zmq.conf
sed -i 's/^tx_gain = 50/tx_gain = 30/' ~/ocudu-lab/ue_zmq.conf
grep -n 'tx_gain' ~/ocudu-lab/ue_zmq.conf
```

Después hay que **reiniciar el teléfono** (porque lee el archivo solo al arrancar) y, por precaución, también el gNB, con **nombres de archivo nuevos** (por ejemplo `gnb_tx30.txt` y `ue_tx30.txt`) para no sobrescribir los anteriores. Resultado: la subida mejoró cerca de un 16 % en una corrida, sin resolver la causa del problema (sección 12).

---

## 11. Cómo leer las tablas de la consola

### Tabla del gNB (la antena)

```
         |---------------DL (bajada)---------------|-------------UL (subida)-------------------
pci rnti | cqi  ri  mcs  brate   ok  nok  (%)  dl_bs | pusch  rsrp  ri  mcs  brate  ok  nok  (%)  bsr  ta  phr
```

| Columna | Qué significa |
| --- | --- |
| `pci`, `rnti` | Identificadores de la celda y del teléfono |
| `cqi` | Calidad del canal que informa el teléfono (1 a 15; 15 = perfecto) |
| `mcs` | **Esquema de modulación y codificación (0 a 28)**: qué tan "apretada" va la información. Más alto = más rápido pero más frágil |
| `brate` | Velocidad (bits por segundo) |
| `ok` / `nok` / `(%)` | Bloques recibidos bien / mal / porcentaje de errores |
| `dl_bs` | Datos esperando en cola para ser enviados al teléfono (bytes) |
| `pusch` | **Calidad de la señal de subida (SINR, en dB)** |
| `rsrp` | Potencia recibida (`ovl` = aviso de nivel, aún sin explicar del todo) |
| `bsr` | Datos que el teléfono dice tener pendientes |
| `ta` | Ajuste de tiempo (distancia) |

### Tabla del teléfono (srsUE)

```
rat pci rsrp pl cfo | mcs snr iter brate bler ta_us | mcs buff brate bler
```

| Columna | Qué significa |
| --- | --- |
| `snr` | Calidad de la señal que recibe el teléfono (dB) |
| `iter` | Intentos que necesita el decodificador (LDPC) para leer cada bloque; cerca de 1 = señal muy limpia |
| `bler` | Porcentaje de bloques con error |
| `buff` | Datos pendientes de subir |

---

## 12. Resultados obtenidos

Todos medidos en este laboratorio (un teléfono, canal virtual ideal, un solo computador).

| Medida | Resultado |
| --- | --- |
| Retardo en reposo, teléfono → core | 30,1 ms de promedio (mín. 18,7, máx. 142) |
| Retardo en reposo, core → teléfono | 28,9 ms (18,4 a 38,9) |
| Retardo a Internet (8.8.8.8) con 5G / sin 5G | 56,2 ms / 24,4 ms (la red 5G añade unos 32 ms) |
| Velocidad TCP de bajada (5 corridas) | 26,4 Mb/s |
| Velocidad TCP de subida (5 corridas) | 5,84 Mb/s |
| Capacidad máxima (UDP) | 27 Mb/s bajada, 6,1 Mb/s subida |
| Retardo máximo con la red llena | 0,90 s (bajada), 0,47 s (subida) |
| CPU | gNB unos 2 núcleos, teléfono 0,7 a 1,2, UPF menos de 0,1 |
| Modulación elegida | Bajada: MCS 28 (el máximo), 0 % de errores. Subida: MCS 5 a 8, cerca del 1 % de errores |

**Qué significan en palabras sencillas**

1. **La bajada rinde al máximo de lo que permite la celda** (10 MHz, modulación 64QAM): unos 29 Mb/s a nivel de radio y 26,4 Mb/s ya como Internet.
2. **La subida es mucho más lenta** porque la señal de subida llega con poca calidad (1 a 4 dB cuando debería ser mucho más alta en un canal virtual sin ruido). **La causa no se encontró**; se descartaron la CPU, las colas del sistema operativo y la ganancia del teléfono por sí sola.
3. **Con la red llena el retardo se dispara (hasta 0,9 s)** porque se forma una cola de unos 2,8 MB dentro del gNB. Una cola enorme no pierde paquetes, pero los hace esperar ("bufferbloat").
4. Las repeticiones de 26,4 Mb/s y 5,8 Mb/s son muy parecidas entre sí, así que los resultados son estables.

---

## 13. Problemas frecuentes y cómo se resolvieron

| Síntoma | Causa | Solución |
| --- | --- | --- |
| MongoDB no arranca | Kernel de Ubuntu 26.04 demasiado nuevo para MongoDB 8.0 | Ajuste de la sección 6.1 |
| El teléfono se conecta pero el ping falla | El cortafuegos bloquea la interfaz `ogstun` | Reglas de la sección 6.5 (se pierden al reiniciar) |
| El gNB falla con `Invalid nof. SSB per RACH occasion value 0.25` | Líneas de PRACH del ejemplo incompatibles | Se eliminaron del `gnb_zmq.yml` (sección 8.1) |
| `t: command not found` | Se escribió `t` en la ventana C | `t` va en la ventana del gNB y en la del teléfono |
| La IP del teléfono cambia | El core asigna la siguiente libre en cada conexión | Recalcular `UE_IP` (paso 5). Para fijarla: poner la IP en el panel web y reiniciar `open5gs-amfd` |
| `iperf3: Address already in use` | Ya hay un servidor iperf3 corriendo | `pgrep -a iperf3` para verlo; si hace falta, `sudo pkill iperf3` y arrancar de nuevo |
| `iperf3: Connection refused` | No hay servidor iperf3 | Arrancarlo en la ventana D (paso 6) |
| Un ping justo después de una prueba da 150 ms | La cola tarda unos segundos en vaciarse | Esperar unos segundos |
| La velocidad baja a 23 Mb/s | Poca memoria disponible | Cerrar programas, `free -h`; se pueden parar servicios de 4G que no se usan: `sudo systemctl stop open5gs-webui open5gs-mmed open5gs-hssd open5gs-pcrfd open5gs-sgwcd open5gs-sgwud` (ojo: sin `open5gs-webui` no hay panel web hasta volver a iniciarlo con `sudo systemctl start open5gs-webui`) |
| El archivo `gnb_ngap.pcap` sale vacío (0 bytes) | Se copió con el gNB aún funcionando | Detener el gNB (`Ctrl+C`) **y luego** copiar: `sudo cp /tmp/gnb_ngap.pcap ~/ocudu-lab/evidencia/` |
| `script` borró datos anteriores | `script` sobrescribe el archivo | Usar nombres nuevos o copiar antes |
| Disco lleno de registros | `all_level: info` genera archivos de 126 a 198 MB | Poner `warning` en ambas configuraciones (ya hecho) |

---

## 14. Apagar todo

En este orden:

1. En la ventana B (teléfono): `Ctrl+C`.
2. En la ventana A (gNB): `Ctrl+C`.
3. En la ventana C, si se usaron:

```bash
sudo pkill tcpdump
sudo pkill iperf3
pgrep -a 'gnb|srsue|iperf3|tcpdump'
```

| Parte | Qué hace |
| --- | --- |
| `pkill <nombre>` | Termina los programas con ese nombre |
| `pgrep -a '...'` | Lista los que sigan vivos; si no sale nada, todo quedó apagado |

El core (Open5GS y MongoDB) puede quedarse encendido: arranca solo con el computador.

---

## 15. Organización del repositorio y ramas (Git)

**Qué es una rama.** Piensen en una copia paralela del proyecto: la rama `ocudu` guarda el trabajo con OCUDU y otra rama (por ejemplo `openran-legacy`) puede guardar el de su compañero con la versión antigua. Se pueden comparar y no se pisan entre sí.

**Estructura sugerida**

```
.
├── README.md            ← este documento
├── config/              ← gnb_zmq.yml, ue_zmq.conf y copias de los .yaml de Open5GS
├── scripts/             ← comandos repetidos convertidos en scripts (pendiente)
├── docs/                ← documento de la Fase 1 y de resultados
└── evidencia/           ← solo archivos pequeños de texto (ping, iperf, tablas)
```

**Lo que NO debe subirse**

GitHub rechaza archivos de más de 100 MB, y las capturas pesan 131 y 143 MB. Creen un archivo `.gitignore` en la raíz:

```
*.pcap
*.log
build/
evidencia/cpu_*.txt
```

(Cada línea es un patrón de archivos que Git ignora. Quitar la de `cpu_*.txt` si quieren subirlos; pesan 16 KB cada uno.) Para compartir las capturas se puede usar Git LFS o un enlace a un almacenamiento externo.

**Primeros comandos de Git**

```bash
git init
git branch -M main
git add README.md .gitignore config/
git commit -m "Agrega README y configuración inicial"
git remote add origin <URL-DEL-REPOSITORIO>
git push -u origin main
git switch -c ocudu
git push -u origin ocudu
```

| Comando | Qué hace |
| --- | --- |
| `git init` | Convierte la carpeta actual en un repositorio |
| `git branch -M main` | Nombra `main` a la rama principal |
| `git add <archivos>` | Marca los archivos que irán en el próximo "paquete" de cambios |
| `git commit -m "mensaje"` | Guarda ese paquete con una descripción |
| `git remote add origin <URL>` | Conecta con el repositorio en GitHub/GitLab |
| `git push -u origin main` | Sube la rama `main` (`-u` recuerda el destino para la próxima vez) |
| `git switch -c ocudu` | **Crea** la rama `ocudu` y se cambia a ella |
| `git push -u origin ocudu` | Sube la rama `ocudu` |

Para copiar las configuraciones del core al repositorio:

```bash
mkdir -p config/open5gs
sudo cp /etc/open5gs/amf.yaml /etc/open5gs/nrf.yaml config/open5gs/
sudo chown $USER: config/open5gs/*
```

(`cp` copia; `chown $USER:` le devuelve la propiedad de los archivos copiados al usuario actual para poder editarlos.)

---

## 16. Pendientes

- Hacer persistentes las reglas del cortafuegos de la sección 6.5 (por ejemplo con `netfilter-persistent save` o un script de arranque).
- Aplicar el script `ocudu_performance` (el gNB avisa que el procesador no está en modo `performance`).
- Probar el tamaño de la cola GTP-U / RLC del gNB para reducir el retardo con la red llena.
- Barrido de calidad de canal desde la consola del gNB (comandos `tx_gain` y `rx_gain`) para ver cómo cambia el MCS.
- Encontrar la causa de la baja calidad de subida.
- Convertir los comandos repetidos en scripts (`scripts/`).
- **Fase 3:** instalar UHD 4.6.0.0, recompilar OCUDU con soporte USRP, programar una SIM real y configurar un teléfono comercial.
- Sección de impacto y ética: la regulación del espectro (en Colombia, la ANE), qué es el PLMN 001/01 de pruebas y la seguridad (contraseña por defecto del panel web). En la Fase 2 no se emite nada por el aire; en la Fase 3 sí hará falta autorización.

---

## 17. Glosario

| Término | En palabras sencillas |
| --- | --- |
| **5G SA** (Standalone) | Una red 5G completa, con núcleo propio 5G (no apoyada en 4G) |
| **Core / núcleo** | El "cerebro" de la red: autentica y conecta |
| **AMF** | La parte del core que recibe a los teléfonos y los registra |
| **SMF / UPF** | SMF organiza las sesiones de datos; UPF mueve el tráfico hacia Internet |
| **gNB** | La estación base (antena) de 5G |
| **UE** | "User Equipment": el teléfono |
| **SDR / USRP** | Radio por software; el USRP es el equipo físico que se usará en la Fase 3 |
| **ZMQ (ZeroMQ)** | Biblioteca que permite simular el radio pasando las señales por la red interna |
| **PLMN** | Código de país + operador (MCC + MNC) |
| **TAC** | Código del área de la antena |
| **Slice (SST)** | "Tipo de servicio" de red virtual |
| **DNN / APN** | Nombre de la puerta de datos (`internet`) |
| **IMSI, K, OPc** | Identidad y claves secretas de la SIM |
| **Namespace** | Una "habitación" de red aislada dentro del computador |
| **GTP-U** | Formato en que viajan los datos del usuario entre la antena y el core |
| **MCS** | Qué tan densa es la modulación; define la velocidad por bloque |
| **SINR / SNR** | Qué tan fuerte es la señal frente al ruido (dB); más alto es mejor |
| **BLER** | Porcentaje de bloques que llegan con error |
| **LDPC / Polar** | Códigos que protegen los datos (LDPC) y la información de control (Polar) |
| **TCP / UDP** | Dos formas de enviar datos: TCP asegura la entrega, UDP solo envía |
| **Bufferbloat** | Cola excesivamente grande: no se pierde nada, pero todo llega tarde |
| **Rama (Git)** | Línea de trabajo paralela dentro de un repositorio |

---

## 18. Puntos a revisar antes de publicar

- [ ] **MongoDB:** anotar los comandos reales con los que se instaló (sección 6.1).
- [ ] **Node.js y panel web:** confirmar que los comandos de la sección 6.6 son los que se usaron.
- [ ] **`gnb_zmq.yml` y `ue_zmq.conf`:** copiar los archivos reales a `config/` (la sección 8 describe sus cambios, no los reemplaza).
- [ ] **Valor actual de `tx_gain`:** quedó en 30 tras el experimento; decidir si se deja o se vuelve a 50.
- [ ] **Datos sensibles:** confirmar que K, OPc e IMSI son solo de pruebas antes de subirlos, y cambiar la contraseña del panel web.
- [ ] **Cifras:** comprobar contra el documento de resultados de la Fase 2.
- [ ] **Capturas `.pcap`:** no subirlas (superan los 100 MB); usar `.gitignore` o Git LFS.
- [ ] **Nombre de la rama de su compañero** (`openran-legacy` es solo una propuesta).