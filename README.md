# Red 5G SA Zero-RF con srsRAN Project 25.10, Open5GS y srsUE

Este documento explica paso a paso cómo desplegar una red **5G SA (Standalone)** de laboratorio utilizando **Open5GS como núcleo 5G**, **srsRAN Project 25.10 como gNB** y **srsUE como equipo de usuario simulado**.

La comunicación entre el gNB y el UE se realiza mediante **ZeroMQ (ZMQ)** en lugar de utilizar inicialmente un SDR y antenas. De esta manera es posible validar el funcionamiento de la red 5G sin realizar transmisiones reales de radiofrecuencia.

El objetivo de este README es que la implementación pueda ser entendida y reproducida por otra persona, explicando no solamente los comandos utilizados, sino también qué significa cada parámetro, por qué se configuró y qué errores se encontraron durante el desarrollo.

> **Importante:** esta rama documenta específicamente la implementación realizada con **srsRAN Project release 25.10**. La implementación alternativa realizada con OCUDU se mantiene en la rama `feature/OCUDU`.

---

# Contenido

1. Descripción general del proyecto
2. Componentes utilizados
3. Arquitectura e interfaces 5G utilizadas
4. Parámetros generales de nuestra red
5. Requisitos del sistema
6. Preparación de Ubuntu
7. Instalación y configuración de MongoDB
8. Instalación y configuración de Open5GS
9. Configuración del abonado 5G
10. Configuración de red, forwarding y NAT
11. Creación del namespace `ue1`
12. Configuración DNS del UE
13. Instalación de dependencias de srsRAN
14. Instalación y compilación de srsRAN Project
15. Instalación y compilación de srsUE
16. Configuración del gNB
17. Configuración de srsUE
18. Automatización del namespace y rutas
19. Procedimiento para iniciar la red
20. Comprobación del registro 5G
21. Pruebas de conectividad
22. Pruebas de rendimiento
23. Logs y evidencias
24. Problemas encontrados y soluciones
25. Procedimiento para detener la red
26. Estructura recomendada del repositorio
27. Seguridad y datos que no deben publicarse
28. Estado actual y trabajo futuro
29. Glosario
30. Referencias

---

# 1. Descripción general del proyecto

El proyecto busca implementar progresivamente una red 5G completa.

La arquitectura utilizada actualmente corresponde a una red **5G SA**, es decir, una red 5G que utiliza directamente un **5G Core (5GC)** y no depende de una infraestructura LTE/EPC para funcionar.

En esta implementación:

- **Open5GS** proporciona el núcleo 5G.
- **srsRAN Project 25.10** proporciona el gNB.
- **srsUE de srsRAN 4G 25.10** simula el terminal 5G.
- **ZeroMQ** reemplaza temporalmente el enlace físico de radio.
- **MongoDB** almacena la información de los abonados registrados en Open5GS.
- Linux utiliza un **network namespace** llamado `ue1` para aislar la red del UE simulado.
- El UE recibe una dirección de la red `10.45.0.0/16`.
- Open5GS permite posteriormente transportar el tráfico del UE hacia Internet.

Esta implementación Zero-RF permite comprobar primero el funcionamiento lógico de la red antes de incorporar un SDR, una SIM física y un teléfono 5G comercial.

---

# 2. Componentes utilizados

| Componente | Software utilizado | Función |
|---|---|---|
| Sistema operativo | Ubuntu 24.04.5 LTS | Plataforma donde se ejecuta toda la red |
| Base de datos | MongoDB 8.0.32 | Almacena los abonados utilizados por Open5GS |
| 5G Core | Open5GS 2.8.0 | Gestiona registro, autenticación, sesiones y tráfico de usuario |
| gNB | srsRAN Project 25.10 | Implementa la estación base 5G |
| UE | srsUE 25.10 | Simula un dispositivo conectado a la red |
| Radio virtual | ZeroMQ | Transporta muestras IQ entre gNB y UE sin RF física |
| Namespace | Linux `ue1` | Aísla la interfaz y las rutas del UE |
| Pruebas | ping | Permite comprobar conectividad y latencia |
| Rendimiento | iperf3 | Permite medir throughput TCP |

## ¿Qué es un gNB?

El **gNB (Next Generation Node B)** es la estación base de una red 5G.

Es el equivalente 5G de una estación base celular y se encarga de la comunicación entre el UE y el núcleo de la red.

En nuestro proyecto el gNB no utiliza todavía una antena. La parte radio se sustituye por ZeroMQ.

## ¿Qué es un UE?

**UE significa User Equipment**.

En una red comercial podría ser:

- un teléfono 5G;
- un módem;
- un router 5G;
- un dispositivo IoT.

En esta etapa utilizamos **srsUE**, por lo que el dispositivo es simulado mediante software.

## ¿Qué significa Zero-RF?

Zero-RF significa que no estamos transmitiendo físicamente señales de radio.

Las muestras digitales que normalmente llegarían al SDR se intercambian directamente entre srsUE y el gNB mediante ZeroMQ.

Esto permite desarrollar y depurar la red sin:

- SDR;
- antenas;
- transmisión RF;
- interferencia sobre redes reales.

---

# 3. Arquitectura e interfaces 5G utilizadas

Nuestra implementación utiliza varias interfaces definidas en la arquitectura 5G.

| Interfaz | Comunicación | Protocolo principal | Función |
|---|---|---|---|
| N1 | UE ↔ AMF | NAS | Señalización lógica entre el UE y el núcleo |
| N2 | gNB ↔ AMF | NGAP sobre SCTP | Señalización entre la estación base y el núcleo |
| N3 | gNB ↔ UPF | GTP-U sobre UDP | Transporte de los datos del usuario |
| N4 | SMF ↔ UPF | PFCP | Control de las sesiones del plano de usuario |
| N6 | UPF ↔ Internet/red externa | IP | Salida del tráfico del UE hacia una red externa |

## N1

La interfaz **N1** es una interfaz lógica entre el UE y el AMF.

Transporta mensajes **NAS (Non-Access Stratum)** relacionados con:

- registro;
- autenticación;
- seguridad;
- movilidad;
- establecimiento de sesiones.

Aunque el mensaje pasa físicamente a través del gNB, conceptualmente la comunicación N1 ocurre entre el UE y el AMF.

## N2

La interfaz **N2** conecta el gNB con el AMF.

Utiliza:

- **NGAP (NG Application Protocol)** para la señalización 5G;
- **SCTP (Stream Control Transmission Protocol)** como transporte.

En nuestra implementación el AMF escucha en:

```text
127.0.0.5:38412
```

El puerto `38412` corresponde a NGAP/SCTP.

## N3

La interfaz **N3** conecta el gNB con el UPF.

Transporta los paquetes del usuario utilizando **GTP-U (GPRS Tunnelling Protocol - User Plane)**.

Open5GS utiliza para el UPF:

```text
127.0.0.7:2152
```

El puerto UDP `2152` se utiliza para GTP-U.

## N4

N4 conecta el SMF y el UPF.

El protocolo utilizado es **PFCP (Packet Forwarding Control Protocol)**.

El SMF utiliza esta interfaz para indicar al UPF cómo manejar el tráfico de las sesiones.

## N6

N6 representa la conexión entre el UPF y una red externa.

En nuestro laboratorio esa red externa es Internet.

---

# 4. Parámetros generales de nuestra red

Estos valores deben mantenerse coherentes entre Open5GS, el gNB y srsUE.

| Parámetro | Nombre | Valor | Significado |
|---|---|---:|---|
| MCC | Mobile Country Code | `999` | Identifica el país o entorno de la red móvil |
| MNC | Mobile Network Code | `70` | Identifica al operador dentro del MCC |
| PLMN | Public Land Mobile Network | `99970` | Identificador de la red formado por MCC + MNC |
| TAC | Tracking Area Code | `1` | Identifica el área de seguimiento donde está el UE |
| SST | Slice/Service Type | `1` | Identifica el tipo de slice solicitado/utilizado |
| SD | Slice Differentiator | No utilizado | Permite diferenciar slices con el mismo SST |
| DNN | Data Network Name | `internet` | Identifica la red de datos a la que accede el UE |
| IMSI | International Mobile Subscriber Identity | `999700000000001` | Identificador único del abonado de laboratorio |
| AMF USIM | Authentication Management Field | `8000` | Campo utilizado durante la autenticación AKA |
| Banda NR | NR Frequency Band | `n3` | Banda NR configurada para la simulación |
| DL ARFCN | NR Absolute Radio Frequency Channel Number | `368500` | Número que identifica la frecuencia central de downlink |
| BW | Channel Bandwidth | `20 MHz` | Ancho total del canal configurado |
| SCS | Subcarrier Spacing | `15 kHz` | Separación entre subportadoras OFDM |
| PRB | Physical Resource Block | `106` | Cantidad de bloques de recursos utilizados con 20 MHz y SCS 15 kHz |
| Sample rate | Tasa de muestreo | `23.04 Msamples/s` | Número de muestras IQ procesadas por segundo |
| UE subnet | Subred del UE | `10.45.0.0/16` | Red IP asignada a las sesiones de usuario |
| DNN session | Red de datos | `internet` | Nombre de la conexión de datos solicitada por srsUE |

A continuación se explica cada parámetro.

## 4.1 MCC — Mobile Country Code

El **MCC** identifica el país o dominio de una red móvil.

En una red comercial existen MCC asignados oficialmente.

Para este laboratorio utilizamos:

```text
MCC = 999
```

porque estamos trabajando con una red privada de laboratorio y no intentando representar un operador comercial real.

El mismo MCC debe aparecer de manera coherente en Open5GS, gNB y los datos del abonado.

---

## 4.2 MNC — Mobile Network Code

El **MNC** identifica una red u operador dentro de un MCC.

Utilizamos:

```text
MNC = 70
```

Al combinarlo con MCC:

```text
MCC = 999
MNC = 70
```

obtenemos nuestro PLMN:

```text
99970
```

---

## 4.3 PLMN — Public Land Mobile Network

El **PLMN** identifica la red móvil.

En nuestro laboratorio:

```text
PLMN = MCC + MNC
PLMN = 999 + 70
PLMN = 99970
```

Por eso el gNB anuncia:

```yaml
plmn: "99970"
```

y Open5GS debe reconocer la misma red.

Si gNB y Core utilizan PLMN diferentes, el UE no estará intentando registrarse en la misma red que gestiona Open5GS.

---

## 4.4 TAC — Tracking Area Code

El **TAC** identifica una Tracking Area.

Una Tracking Area agrupa una o varias celdas y permite al núcleo saber aproximadamente en qué área se encuentra un UE.

En nuestro laboratorio solo necesitamos una:

```text
TAC = 1
```

Debe coincidir entre la configuración del AMF y la del gNB.

---

## 4.5 SST — Slice/Service Type

El **SST** identifica el tipo de servicio de un Network Slice.

Utilizamos:

```text
SST = 1
```

SST 1 corresponde normalmente al tipo de servicio **eMBB (enhanced Mobile Broadband)**.

En nuestro laboratorio no estamos implementando una arquitectura compleja con múltiples slices.

---

## 4.6 SD — Slice Differentiator

El **SD** permite diferenciar varios slices que tengan el mismo SST.

En nuestra implementación:

```text
SD = no utilizado
```

Este punto fue importante durante el diagnóstico.

Inicialmente srsUE estaba solicitando:

```text
SST = 1
SD = 1
```

pero Open5GS no tenía configurado ese S-NSSAI específico.

El AMF mostraba:

```text
Cannot find Requested NSSAI [1]
Registration reject [62]
```

Por esta razón se desactivó la solicitud explícita de slicing en srsUE.

La configuración utilizada finalmente se encuentra explicada en la **Sección 17.6**.

---

## 4.7 DNN — Data Network Name

El **DNN** identifica la red de datos a la cual quiere conectarse el UE.

Puede entenderse de manera similar al APN utilizado tradicionalmente en redes móviles.

Utilizamos:

```text
DNN = internet
```

El mismo nombre debe configurarse en Open5GS y solicitarse desde srsUE.

---

## 4.8 IMSI

**IMSI significa International Mobile Subscriber Identity.**

Es el identificador del abonado.

Nuestro abonado de laboratorio utiliza:

```text
999700000000001
```

Este IMSI debe coincidir entre:

- el subscriber creado en Open5GS;
- la USIM configurada en srsUE.

Las credenciales criptográficas asociadas al IMSI no deben publicarse.

---

## 4.9 Banda NR n3

La banda indica el rango de frecuencias utilizado por NR.

Para la simulación utilizamos:

```text
band = 3
```

correspondiente a NR band n3.

Aunque estamos en Zero-RF y no estamos transmitiendo realmente esa frecuencia, srsRAN sigue necesitando una configuración radio coherente para generar y procesar la señal NR simulada.

---

## 4.10 DL ARFCN

**ARFCN significa Absolute Radio Frequency Channel Number.**

En lugar de escribir directamente una frecuencia en Hz, NR utiliza un número de canal que puede convertirse matemáticamente en una frecuencia.

Utilizamos:

```text
dl_arfcn = 368500
```

Este valor pertenece al escenario de banda n3 utilizado en nuestra configuración Zero-RF.

---

## 4.11 BW — Channel Bandwidth

El ancho de banda del canal configurado es:

```text
20 MHz
```

Este parámetro determina cuánto espectro ocupa el canal NR simulado.

No debe confundirse con el throughput obtenido por iperf3.

Tener un canal de 20 MHz no significa que automáticamente se obtengan 20 Mbit/s ni ninguna velocidad específica.

---

## 4.12 SCS — Subcarrier Spacing

5G NR utiliza OFDM.

El canal se divide en múltiples subportadoras y el parámetro **SCS** indica la separación entre ellas.

Utilizamos:

```text
SCS = 15 kHz
```

En srsRAN:

```yaml
common_scs: 15
```

---

## 4.13 PRB — Physical Resource Block

Un **PRB (Physical Resource Block)** es una unidad utilizada para asignar recursos radio.

Cada PRB contiene:

```text
12 subportadoras
```

Con:

```text
BW = 20 MHz
SCS = 15 kHz
```

nuestra configuración utiliza:

```text
106 PRB
```

Por eso srsUE contiene:

```ini
max_nof_prb = 106
nof_prb = 106
```

Los PRB representan recursos de la cuadrícula NR y no deben interpretarse directamente como una velocidad de datos.

---

## 4.14 Sample rate

ZeroMQ intercambia muestras IQ digitales.

Nuestra tasa es:

```text
23.04 Msamples/s
```

es decir:

```text
23.04 millones de muestras por segundo
```

Debe coincidir entre gNB y srsUE.

gNB:

```yaml
base_srate=23.04e6
srate: 23.04
```

srsUE:

```ini
base_srate=23.04e6
```

Una discrepancia entre ambos extremos puede impedir que la capa física funcione correctamente.

---

# 5. Requisitos del sistema

La implementación fue validada con:

| Componente | Versión utilizada |
|---|---|
| Ubuntu | 24.04.5 LTS |
| Kernel Linux | `6.8.0-146-generic` |
| MongoDB | 8.0.32 |
| Open5GS | 2.8.0 |
| srsRAN Project | 25.10.0 |
| srsRAN 4G / srsUE | 25.10.0 |
| ZeroMQ | `libzmq3-dev` |
| iperf3 | 3.16 |

Se recomienda conservar estas versiones si se busca reproducir exactamente el montaje.

---

# 6. Preparación de Ubuntu

El proyecto se desarrolló sobre Ubuntu instalado de forma nativa.

Antes de instalar los componentes:

```bash
sudo apt update
sudo apt upgrade
```

Comprobar el kernel:

```bash
uname -r
```

En nuestro entorno validado:

```text
6.8.0-146-generic
```

## Problema encontrado con kernel 7.0

Durante el montaje se arrancó inicialmente con:

```text
7.0.0-38
```

MongoDB 8.0.32 no funcionó correctamente con ese kernel en nuestro entorno.

Instalamos la rama 6.8:

```bash
sudo apt install linux-generic-6.8
```

Después reiniciamos y seleccionamos el kernel 6.8 desde GRUB.

Por esta razón, antes de diagnosticar Open5GS o MongoDB siempre recomendamos ejecutar:

```bash
uname -r
```

---

# 7. Instalación y configuración de MongoDB

Open5GS utiliza MongoDB para almacenar información de los abonados.

La instalación debe realizarse siguiendo las instrucciones oficiales correspondientes a Ubuntu y a la versión de MongoDB utilizada.

Después de instalar:

```bash
mongod --version
```

En nuestro caso:

```text
MongoDB 8.0.32
```

Comprobar el servicio:

```bash
systemctl status mongod
```

Debe aparecer:

```text
active (running)
```

También puede comprobarse rápidamente con:

```bash
systemctl is-active mongod
```

Resultado esperado:

```text
active
```

Si MongoDB no inicia, revisar primero el kernel según la **Sección 6**.

---

# 8. Instalación y configuración de Open5GS

## 8.1 Instalación

Se utilizó el repositorio recomendado por Open5GS:

```bash
sudo add-apt-repository ppa:open5gs/latest
sudo apt update
sudo apt install open5gs
```

Comprobar:

```bash
open5gs-amfd -v
```

En nuestro entorno:

```text
Open5GS v2.8.0
```

---

## 8.2 Funciones principales del 5G Core

Entre las funciones utilizadas se encuentran:

| Función | Nombre | Papel |
|---|---|---|
| AMF | Access and Mobility Management Function | Registro, conexión y movilidad del UE |
| SMF | Session Management Function | Creación y control de PDU Sessions |
| UPF | User Plane Function | Transporta los paquetes del usuario |
| AUSF | Authentication Server Function | Participa en la autenticación |
| UDM | Unified Data Management | Gestiona información del abonado |
| UDR | Unified Data Repository | Repositorio de datos |
| NRF | Network Repository Function | Registro y descubrimiento de Network Functions |

Comprobar servicios:

```bash
systemctl --no-pager --type=service --state=running | \
grep -E "open5gs-(amf|smf|upf|nrf|ausf|udm|udr)"
```

---

## 8.3 AMF

El AMF debe utilizar los parámetros descritos en la **Sección 4**:

```text
MCC = 999
MNC = 70
TAC = 1
SST = 1
```

La interfaz N2 escucha en:

```text
127.0.0.5:38412
```

El gNB utilizará exactamente esa dirección en la **Sección 16**.

---

## 8.4 SMF

La sesión de datos utiliza:

```text
DNN = internet
UE subnet = 10.45.0.0/16
Gateway = 10.45.0.1
DNS = 8.8.8.8 / 8.8.4.4
MTU = 1400
```

**MTU** significa Maximum Transmission Unit y determina el tamaño máximo de un paquete IP que puede atravesar la interfaz sin fragmentación adicional.

---

## 8.5 UPF

El UPF utiliza:

```text
PFCP = 127.0.0.7:8805
GTP-U = 127.0.0.7:2152
UE subnet = 10.45.0.0/16
```

La interfaz del UPF se denomina:

```text
ogstun
```

Comprobar:

```bash
ip addr show ogstun
```

Debe contener:

```text
10.45.0.1/16
```

---

# 9. Configuración del abonado 5G

## 9.1 Instalar WebUI

Se utilizó:

```bash
curl -fsSL https://open5gs.org/open5gs/assets/webui/install | sudo -E bash -
```

Abrir:

```text
http://localhost:9999
```

## 9.2 Crear subscriber

Crear un subscriber con:

| Campo | Valor |
|---|---|
| IMSI | `999700000000001` |
| K | `<K_DE_PRUEBA>` |
| AMF | `8000` |
| USIM Type | OPc |
| OPc | `<OPC_DE_PRUEBA>` |
| SST | `1` |
| SD | vacío |
| Default S-NSSAI | habilitado |
| DNN/APN | `internet` |
| Session Type | IPv4 |
| 5QI | `9` |
| ARP | `8` |

Los conceptos MCC, MNC, IMSI, SST, SD y DNN están explicados en la **Sección 4**.

## ¿Qué es 5QI?

**5QI significa 5G QoS Identifier.**

Identifica un conjunto de características de calidad de servicio.

Utilizamos:

```text
5QI = 9
```

como configuración de datos de propósito general del laboratorio.

## ¿Qué es ARP?

**ARP, en este contexto, significa Allocation and Retention Priority.**

No debe confundirse con el protocolo Ethernet Address Resolution Protocol.

Este ARP indica la prioridad utilizada para decidir la asignación y retención de recursos asociados a QoS.

En nuestro subscriber:

```text
ARP = 8
```

---

# 10. Configuración de red, forwarding y NAT

Para que el tráfico del UE pueda salir hacia Internet, Linux debe actuar como router.

## 10.1 Activar IPv4 forwarding

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Comprobar:

```bash
sysctl net.ipv4.ip_forward
```

Resultado:

```text
net.ipv4.ip_forward = 1
```

## 10.2 NAT

El UE utiliza direcciones privadas:

```text
10.45.0.0/16
```

Para salir a Internet se utiliza NAT mediante MASQUERADE.

En nuestro computador la interfaz Wi-Fi fue:

```text
wlo1
```

Regla:

```bash
sudo iptables -t nat -A POSTROUTING \
-s 10.45.0.0/16 -o wlo1 -j MASQUERADE
```

Antes de copiar esta regla en otro equipo comprobar:

```bash
ip route
```

porque la interfaz podría llamarse:

```text
wlan0
wlp...
eth0
enp...
```

## 10.3 Persistencia

En nuestro equipo esta configuración se dejó persistente mediante un servicio:

```text
open5gs-nat.service
```

Así no es necesario recrear manualmente la regla después de cada reinicio.

---

# 11. Creación del namespace `ue1`

Un **network namespace** permite tener una pila de red Linux aislada.

Creamos uno llamado:

```text
ue1
```

para representar la red del UE.

Manualmente:

```bash
sudo ip netns add ue1
```

Comprobar:

```bash
sudo ip netns list
```

Debe aparecer:

```text
ue1
```

## Problema encontrado

Los namespaces creados de esta manera desaparecen después de reiniciar Linux.

Por eso se creó un servicio systemd.

Archivo:

```text
/etc/systemd/system/ue1-netns.service
```

Contenido:

```ini
[Unit]
Description=Create network namespace for srsUE
Before=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '/usr/sbin/ip netns list | grep -qw ue1 || /usr/sbin/ip netns add ue1'
ExecStop=/bin/sh -c '/usr/sbin/ip netns delete ue1 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
```

Activar:

```bash
sudo systemctl daemon-reload
sudo systemctl enable ue1-netns.service
sudo systemctl start ue1-netns.service
```

Comprobar:

```bash
systemctl status ue1-netns.service
ip netns list
```

`active (exited)` es correcto porque es un servicio `oneshot`: ejecuta una tarea y termina, pero systemd conserva su estado como activo gracias a `RemainAfterExit=yes`.

---

# 12. Configuración DNS del UE

Después de conseguir acceso a Internet por IP encontramos otro problema:

```bash
sudo ip netns exec ue1 ping 8.8.8.8
```

funcionaba, pero:

```bash
sudo ip netns exec ue1 ping google.com
```

no.

El namespace estaba utilizando:

```text
nameserver 127.0.0.53
```

Este corresponde al stub de `systemd-resolved` del host.

Dentro del namespace no funcionaba como resolver DNS.

Creamos:

```bash
sudo mkdir -p /etc/netns/ue1
sudo nano /etc/netns/ue1/resolv.conf
```

Contenido:

```text
nameserver 8.8.8.8
nameserver 8.8.4.4
```

Comprobar:

```bash
sudo ip netns exec ue1 cat /etc/resolv.conf
```

Después:

```bash
sudo ip netns exec ue1 ping -c 4 google.com
```

---

# 13. Instalación de dependencias de srsRAN

Instalar:

```bash
sudo apt update

sudo apt install -y \
build-essential \
cmake \
ninja-build \
pkg-config \
libfftw3-dev \
libmbedtls-dev \
libboost-program-options-dev \
libyaml-cpp-dev \
libgtest-dev \
libzmq3-dev \
libuhd-dev \
libsctp-dev \
libconfig++-dev \
libssl-dev
```

Algunas dependencias importantes:

| Dependencia | Función |
|---|---|
| `build-essential` | Compiladores y herramientas básicas |
| `cmake` | Generación del sistema de compilación |
| `ninja-build` | Compilación eficiente de srsRAN Project |
| `libfftw3-dev` | Transformadas FFT utilizadas en procesamiento de señal |
| `libzmq3-dev` | Soporte ZeroMQ |
| `libsctp-dev` | Soporte SCTP necesario para N2 |
| `libuhd-dev` | Soporte UHD para hardware SDR compatible |
| `libyaml-cpp-dev` | Lectura de configuraciones YAML |
| `libssl-dev` | Funciones criptográficas |

---

# 14. Instalación y compilación de srsRAN Project

Crear carpeta:

```bash
mkdir -p ~/5g-project
cd ~/5g-project
```

Clonar:

```bash
git clone https://github.com/srsran/srsRAN_Project.git
cd srsRAN_Project
```

Seleccionar la versión utilizada:

```bash
git checkout release_25_10
```

Comprobar:

```bash
git rev-parse HEAD
```

Nuestra versión corresponde al commit:

```text
d2f4b70dda...
```

Crear build:

```bash
mkdir -p build
cd build
```

Configurar:

```bash
cmake .. -G Ninja -DENABLE_EXPORT=ON -DENABLE_ZEROMQ=ON
```

Aquí:

- `-G Ninja` selecciona Ninja como sistema de compilación.
- `ENABLE_EXPORT=ON` habilita componentes necesarios para esta compilación.
- `ENABLE_ZEROMQ=ON` habilita la radio virtual ZeroMQ.

Compilar:

```bash
ninja
```

Comprobar:

```bash
./apps/gnb/gnb --version
```

Debe mostrar la versión 25.10.0.

---

# 15. Instalación y compilación de srsUE

srsUE se encuentra en srsRAN 4G.

```bash
cd ~/5g-project
git clone https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G
git checkout release_25_10
```

Crear build:

```bash
mkdir -p build
cd build
```

Configurar:

```bash
cmake ..
```

Compilar srsUE:

```bash
make -j"$(nproc)" srsue
```

`$(nproc)` obtiene la cantidad de procesadores lógicos disponibles para realizar la compilación en paralelo.

Comprobar:

```bash
./srsue/src/srsue --version
```

Debe mostrar:

```text
Version 25.10.0
```

y entre los plugins activos debe aparecer ZeroMQ:

```text
libsrsran_rf_zmq.so
```

> Las extensiones 5G de srsUE están destinadas a experimentación y pruebas. No representan un UE 5G comercial completo.

---

# 16. Configuración del gNB

Nuestro archivo es:

```text
~/5g-project/srsRAN_Project/gnb-5g-zmq.yml
```

## 16.1 AMF

```yaml
cu_cp:
  inactivity_timer: 7200

  amf:
    addr: 127.0.0.5
    port: 38412
    bind_addr: 127.0.0.1
```

`addr` es la dirección del AMF de Open5GS.

`port 38412` corresponde a NGAP/SCTP.

`bind_addr` es la dirección local utilizada por el gNB.

El temporizador se explica en la **Sección 16.5**.

## 16.2 Tracking Area y Slice

La configuración debe utilizar los valores de la **Sección 4**:

```yaml
supported_tracking_areas:
  - tac: 1
    plmn_list:
      - plmn: "99970"
        tai_slice_support_list:
          - sst: 1
```

Aquí:

- `tac: 1` identifica nuestra Tracking Area.
- `plmn: "99970"` representa MCC 999 + MNC 70.
- `sst: 1` indica el tipo de slice soportado.

## 16.3 ZeroMQ

```yaml
ru_sdr:
  device_driver: zmq
  device_args: tx_port=tcp://127.0.0.1:2000,rx_port=tcp://127.0.0.1:2001,base_srate=23.04e6
  clock: default
  srate: 23.04
  tx_gain: 80
  rx_gain: 40
```

`device_driver: zmq` indica que no utilizaremos un SDR físico.

Puertos:

```text
gNB TX = 2000
gNB RX = 2001
```

La correspondencia con srsUE se explica en la **Sección 17.2**.

`base_srate` y `srate` corresponden a la tasa de muestreo explicada en la **Sección 4.14**.

Los parámetros `tx_gain` y `rx_gain` representan ganancias configuradas en la interfaz SDR. En ZeroMQ no deben interpretarse como potencia RF real emitida por una antena.

## 16.4 Celda NR

```yaml
cell_cfg:
  dl_arfcn: 368500
  band: 3
  channel_bandwidth_MHz: 20
  common_scs: 15
  plmn: "99970"
  tac: 1
```

Cada parámetro está explicado en la **Sección 4**.

También utilizamos:

```yaml
pdcch:
  dedicated:
    ss2_type: common
    dci_format_0_1_and_1_1: false
  common:
    ss0_index: 0
    coreset0_index: 12

prach:
  prach_config_index: 1

pdsch:
  mcs_table: qam64

pusch:
  mcs_table: qam64
```

### PDCCH

**PDCCH significa Physical Downlink Control Channel.**

Transporta información de control desde el gNB hacia el UE.

### CORESET

**CORESET significa Control Resource Set.**

Define recursos tiempo-frecuencia donde puede transmitirse el PDCCH.

### PRACH

**PRACH significa Physical Random Access Channel.**

Se utiliza durante el procedimiento inicial de acceso aleatorio mediante el cual el UE comienza a establecer comunicación con la celda.

### PDSCH

**PDSCH significa Physical Downlink Shared Channel.**

Transporta principalmente datos en downlink.

### PUSCH

**PUSCH significa Physical Uplink Shared Channel.**

Transporta principalmente datos en uplink.

### MCS

**MCS significa Modulation and Coding Scheme.**

La configuración:

```yaml
mcs_table: qam64
```

selecciona una tabla MCS.

No significa que todas las transmisiones estén utilizando permanentemente 64-QAM.

El scheduler puede seleccionar dinámicamente diferentes índices dentro de la tabla.

Por eso debemos diferenciar:

- tabla MCS configurada;
- índice MCS seleccionado;
- orden de modulación;
- tasa de codificación;
- condiciones observadas del enlace.

## 16.5 Temporizador de inactividad

Durante nuestras primeras pruebas, después de un periodo sin tráfico aparecía:

```text
BearerContextInactivityNotification
UEContextReleaseRequest
UEContextReleaseCommand
rrcRelease
Tunnel removed
```

El UE quedaba registrado anteriormente, pero srsUE no recuperaba de forma fiable el user plane simplemente generando nuevamente tráfico desde `tun_srsue`.

Para disponer de una ventana suficientemente larga de pruebas configuramos:

```yaml
cu_cp:
  inactivity_timer: 7200
```

7200 segundos corresponden a:

```text
120 minutos = 2 horas
```

No estamos deshabilitando el mecanismo de inactividad.

Estamos utilizando un temporizador largo para el laboratorio.

---

# 17. Configuración de srsUE

Archivo:

```text
~/5g-project/srsRAN_4G/build/ue-5g-zmq.conf
```

## 17.1 Radio

```ini
[rf]
device_name = zmq
device_args = tx_port=tcp://127.0.0.1:2001,rx_port=tcp://127.0.0.1:2000,base_srate=23.04e6
```

Esto indica que srsUE utilizará ZeroMQ.

## 17.2 Correspondencia ZMQ

gNB:

```text
TX = 2000
RX = 2001
```

UE:

```text
TX = 2001
RX = 2000
```

Por lo tanto:

```text
gNB TX 2000 → UE RX 2000
UE TX 2001  → gNB RX 2001
```

Durante el diagnóstico decidimos utilizar explícitamente:

```text
127.0.0.1
```

en ambos extremos en lugar de mezclar `*`, `localhost` y `127.0.0.1`.

## 17.3 Desactivar LTE

```ini
[rat.eutra]
dl_earfcn = 3350
nof_carriers = 0
```

La parte importante es:

```text
nof_carriers = 0
```

por lo que no estamos utilizando una portadora LTE.

## 17.4 Activar NR

```ini
[rat.nr]
bands = 3
nof_carriers = 1
max_nof_prb = 106
nof_prb = 106
```

Los conceptos banda y PRB están explicados en las **Secciones 4.9 y 4.13**.

## 17.5 NAS y DNN

```ini
[nas]
apn = internet
apn_protocol = ipv4
```

Aquí srsUE solicita:

```text
DNN/APN = internet
IPv4
```

Debe coincidir con la configuración del subscriber de la **Sección 9**.

## 17.6 Slicing

Configuración final:

```ini
[slicing]
enable = false
#nssai-sst = 1
#nssai-sd = 1
```

Inicialmente teníamos slicing explícito activado.

srsUE solicitaba:

```text
SST = 1
SD = 1
```

pero Open5GS no tenía ese SD configurado.

El AMF rechazaba el registro con:

```text
Cannot find Requested NSSAI [1]
Registration reject [62]
```

Después de desactivar esa solicitud explícita, el UE completó correctamente el registro.

SST y SD están explicados en las **Secciones 4.5 y 4.6**.

## 17.7 Namespace

```ini
[gw]
netns = ue1
```

Esto hace que la interfaz de red del UE sea creada dentro del namespace `ue1` preparado en la **Sección 11**.

---

# 18. Automatización del namespace y rutas

## 18.1 Problema de la ruta

Cuando srsUE establece correctamente una sesión crea:

```text
tun_srsue
```

dentro de `ue1`.

La interfaz recibe una dirección:

```text
10.45.0.x
```

Sin embargo, necesitábamos instalar una ruta por defecto.

Manualmente:

```bash
sudo ip netns exec ue1 ip route add default dev tun_srsue
```

El problema es que al cerrar srsUE desaparece `tun_srsue`.

Linux elimina entonces las rutas asociadas a esa interfaz.

Por eso automatizamos el proceso.

## 18.2 Script `configure-srsue-route.sh`

Crear:

```text
/usr/local/sbin/configure-srsue-route.sh
```

Contenido:

```bash
#!/bin/bash

for i in {1..60}; do
    if ip netns exec ue1 ip link show tun_srsue >/dev/null 2>&1; then
        ip netns exec ue1 ip route replace default dev tun_srsue
        exit 0
    fi

    sleep 1
done

echo "tun_srsue no apareció dentro de ue1 después de 60 segundos"
exit 1
```

Permiso:

```bash
sudo chmod +x /usr/local/sbin/configure-srsue-route.sh
```

El script espera hasta 60 segundos a que srsUE cree `tun_srsue`.

Cuando aparece, ejecuta:

```bash
ip route replace default dev tun_srsue
```

## 18.3 Script `start-srsue.sh`

Crear:

```text
/usr/local/sbin/start-srsue.sh
```

Contenido:

```bash
#!/bin/bash

if ! ip netns list | grep -qw ue1; then
    echo "ERROR: El namespace ue1 no existe."
    exit 1
fi

/usr/local/sbin/configure-srsue-route.sh &

cd /home/david/5g-project/srsRAN_4G/build || exit 1
exec ./srsue/src/srsue ue-5g-zmq.conf
```

Permiso:

```bash
sudo chmod +x /usr/local/sbin/start-srsue.sh
```

> La ruta `/home/david/` corresponde al usuario utilizado en nuestro computador. Debe modificarse si se reproduce el proyecto con otro usuario.

## 18.4 Error `203/EXEC`

Inicialmente systemd no podía ejecutar uno de los scripts.

El problema era que faltaba permiso de ejecución.

Se solucionó con:

```bash
sudo chmod +x /usr/local/sbin/configure-srsue-route.sh
```

Por eso, si aparece:

```text
status=203/EXEC
```

una de las primeras comprobaciones debe ser:

```bash
ls -l /usr/local/sbin/configure-srsue-route.sh
```

---

# 19. Procedimiento para iniciar la red

Después de reiniciar el computador:

## Paso 1 — comprobar kernel

```bash
uname -r
```

En nuestro equipo:

```text
6.8.0-146-generic
```

## Paso 2 — comprobar MongoDB y Open5GS

```bash
systemctl is-active mongod
systemctl is-active open5gs-amfd
systemctl is-active open5gs-smfd
systemctl is-active open5gs-upfd
```

Resultado esperado:

```text
active
active
active
active
```

## Paso 3 — comprobar `ue1`

```bash
ip netns list
```

Debe aparecer:

```text
ue1
```

## Paso 4 — iniciar srsUE

Primera terminal:

```bash
sudo /usr/local/sbin/start-srsue.sh
```

Dejarla abierta.

## Paso 5 — iniciar gNB

Segunda terminal:

```bash
cd ~/5g-project/srsRAN_Project/build
sudo ./apps/gnb/gnb -c ../gnb-5g-zmq.yml
```

En nuestra combinación concreta el orden:

```text
srsUE primero
gNB después
```

resultó más estable durante las pruebas ZMQ.

Esto se documenta como comportamiento operativo observado en nuestro laboratorio, no como una regla general del estándar 5G.

---

# 20. Comprobación del registro 5G

El gNB debe conectarse al AMF.

Un mensaje esperado es:

```text
N2: Connection to AMF on 127.0.0.5:38412 completed
```

Consultar AMF:

```bash
sudo journalctl -u open5gs-amfd -f
```

Cuando el proceso funciona debe observarse:

```text
Registration complete
```

y la creación de la sesión correspondiente.

## Comprobar interfaz UE

```bash
sudo ip netns exec ue1 ip addr show tun_srsue
```

Debe existir una dirección:

```text
10.45.0.x
```

## Comprobar rutas

```bash
sudo ip netns exec ue1 ip route
```

Debe aparecer:

```text
default dev tun_srsue
```

---

# 21. Pruebas de conectividad

Las pruebas deben realizarse progresivamente.

## 21.1 UE → UPF

```bash
sudo ip netns exec ue1 ping -c 4 10.45.0.1
```

Esto comprueba el camino del UE hasta la interfaz `ogstun` del UPF.

## 21.2 UE → Internet por IP

```bash
sudo ip netns exec ue1 ping -c 10 8.8.8.8
```

Si funciona:

- PDU Session funciona;
- user plane funciona;
- forwarding funciona;
- NAT funciona;
- existe conectividad externa.

## 21.3 DNS

```bash
sudo ip netns exec ue1 ping -c 4 google.com
```

Si `8.8.8.8` funciona pero `google.com` no, revisar la **Sección 12**.

---

# 22. Pruebas de rendimiento

Se utilizó `iperf3`.

Si no está instalado:

```bash
sudo apt update
sudo apt install iperf3
```

## 22.1 Servidor

En el host:

```bash
iperf3 -s
```

Por defecto escucha en:

```text
TCP 5201
```

## 22.2 Encontrar IP del host

En nuestro computador la interfaz era `wlo1`.

```bash
ip -4 addr show wlo1
```

En una prueba obtuvimos:

```text
192.168.10.16
```

Esta dirección puede cambiar y no debe codificarse como un valor fijo.

## 22.3 Uplink

```bash
sudo ip netns exec ue1 iperf3 -c <IP_HOST> -t 15
```

El tráfico viaja desde UE hacia el servidor.

Resultado experimental:

```text
≈ 10.5 Mbit/s
```

## 22.4 Downlink

```bash
sudo ip netns exec ue1 iperf3 -c <IP_HOST> -t 15 -R
```

`-R` invierte la dirección del tráfico.

Resultado experimental:

```text
≈ 48.9 Mbit/s
```

Estos resultados corresponden a nuestra ejecución Zero-RF.

No representan el throughput máximo teórico de una red 5G comercial.

---

# 23. Logs y evidencias

El gNB genera:

```text
/tmp/gnb.log
```

Puede inspeccionarse con:

```bash
grep -i -E "zmq|radio|PBCH|PUSCH|PUCCH|SINR|CRC|C-RNTI" \
/tmp/gnb.log | tail -n 30
```

## PBCH

**Physical Broadcast Channel.**

Permite al UE obtener información esencial para acceder inicialmente a la celda.

Durante nuestras pruebas srsUE consiguió decodificar PBCH correctamente.

## PUCCH

**Physical Uplink Control Channel.**

Transporta información de control desde el UE hacia el gNB.

Se observó aproximadamente:

```text
SINR = 11.3 dB
```

en una transmisión PUCCH Format 2.

## SINR

**Signal-to-Interference-plus-Noise Ratio.**

Relaciona la potencia útil recibida con interferencia y ruido.

Un SINR mayor generalmente permite utilizar esquemas de transmisión más eficientes, aunque la selección real depende de más factores.

En nuestro escenario Zero-RF debe interpretarse dentro del entorno simulado, no como una medición de propagación física de una antena real.

## C-RNTI

**Cell Radio Network Temporary Identifier.**

Es un identificador temporal que el gNB utiliza para identificar al UE dentro de la celda.

Durante las pruebas se observó:

```text
C-RNTI = 0x4601
```

---

# 24. Problemas encontrados y soluciones

| Síntoma | Causa encontrada | Solución |
|---|---|---|
| MongoDB no inicia | Kernel utilizado inicialmente incompatible con MongoDB 8.0.32 en nuestro entorno | Utilizar kernel 6.8 validado |
| srsUE se queda en `Switching on` | Comunicación ZMQ no avanzaba correctamente | Configuración explícita `127.0.0.1` y orden de arranque validado |
| `Registration reject [62]` | UE solicitaba SD=1 no configurado | Desactivar slicing explícito |
| `ue1` desaparece al reiniciar | Los namespaces no persisten automáticamente | `ue1-netns.service` |
| UE obtiene IP pero no tiene default route | Ruta no creada automáticamente | `configure-srsue-route.sh` |
| Ruta desaparece al cerrar srsUE | Se destruye `tun_srsue` | Recrear ruta en cada inicio |
| `203/EXEC` | Script sin permiso de ejecución | `chmod +x` |
| Ping por IP funciona pero dominio no | DNS `127.0.0.53` no funciona dentro del namespace | `/etc/netns/ue1/resolv.conf` |
| UE pierde user plane después de inactividad | Liberación del contexto RRC | `inactivity_timer: 7200` |
| Registro funciona pero Internet no | Problema de ruta, forwarding o NAT | Revisar Secciones 10, 18 y 21 |
| No aparece un MCS concreto en logs simples | `mcs_table` no es un MCS medido | No inventar el valor; obtener métricas apropiadas |

## Orden recomendado de diagnóstico

Cuando algo falle, comprobar:

1. Kernel.
2. MongoDB.
3. Open5GS.
4. Namespace `ue1`.
5. ZeroMQ.
6. Conexión N2.
7. Registro NAS.
8. PDU Session.
9. `tun_srsue`.
10. Ruta por defecto.
11. Ping a `10.45.0.1`.
12. Ping a una IP externa.
13. DNS.
14. Rendimiento.

Evitar cambiar varias configuraciones simultáneamente porque dificulta identificar la causa real.

---

# 25. Procedimiento para detener la red

Detener srsUE:

```text
Ctrl+C
```

Detener gNB:

```text
Ctrl+C
```

Si `iperf3` continúa activo:

```bash
pkill iperf3
```

Comprobar:

```bash
pgrep -a 'gnb|srsue|iperf3'
```

MongoDB y Open5GS pueden permanecer activos porque son servicios del sistema.

---

# 26. Estructura recomendada del repositorio

Las dos implementaciones se mantienen en ramas independientes:

```text
main
feature/OCUDU
feature/srsRAN
```

Esta rama corresponde a:

```text
feature/srsRAN
```

Estructura recomendada:

```text
README.md
.gitignore

config/
    gnb-5g-zmq.yml
    ue-5g-zmq.conf

    open5gs/
        amf.yaml
        smf.yaml
        upf.yaml

scripts/
    start-srsue.sh
    configure-srsue-route.sh
    ue1-netns.service

docs/

evidencia/
```

No es necesario subir los repositorios compilados completos de srsRAN.

El README ya explica cómo clonarlos y compilarlos.

---

# 27. Seguridad y datos que no deben publicarse

Antes de utilizar:

```bash
git add .
```

revisar cuidadosamente el contenido.

No publicar credenciales reales como:

- K;
- OP;
- OPc;
- ADM;
- credenciales de una SIM física;
- contraseñas;
- tokens;
- claves privadas.

`.gitignore` recomendado:

```gitignore
# Compilaciones
build/
target/

# Logs y capturas
*.log
*.pcap
*.pcapng

# Temporales
*.tmp
*.swp
*~

# IDE / sistema
.vscode/
.idea/
.DS_Store
Thumbs.db

# Secretos
.env
.env.*
*.secret
*.secrets
config/private/
```

> `.gitignore` no elimina un secreto que ya haya sido incluido anteriormente en el historial de Git. Los archivos deben revisarse antes del primer commit.

---

# 28. Estado actual y trabajo futuro

Actualmente se ha validado:

- Open5GS;
- MongoDB;
- gNB;
- srsUE;
- ZeroMQ;
- N2;
- registro 5G;
- PDU Session;
- user plane;
- acceso a Internet;
- DNS;
- latencia;
- throughput UL/DL.

Los siguientes pasos generales del proyecto incluyen:

- análisis detallado de protocolos;
- análisis de MCS y codificación;
- integración de SDR;
- configuración RF;
- programación de SIM;
- sustitución de srsUE por un teléfono comercial;
- mediciones OTA;
- comparación con la implementación OCUDU.

Cuando el gNB y el Core se ejecuten en equipos diferentes, las direcciones loopback `127.x.x.x` deberán sustituirse por direcciones alcanzables entre los computadores.

---

# 29. Glosario

| Sigla | Nombre | Explicación |
|---|---|---|
| 5G SA | 5G Standalone | Red 5G que utiliza directamente un 5G Core |
| 5GC | 5G Core | Núcleo de una red 5G |
| AMF | Access and Mobility Management Function | Gestiona acceso, registro y movilidad |
| SMF | Session Management Function | Gestiona las sesiones de datos |
| UPF | User Plane Function | Transporta el tráfico del usuario |
| AUSF | Authentication Server Function | Participa en autenticación 5G |
| UDM | Unified Data Management | Gestiona información del abonado |
| UDR | Unified Data Repository | Almacena datos utilizados por funciones del Core |
| NRF | Network Repository Function | Permite registro y descubrimiento de funciones del Core |
| gNB | Next Generation Node B | Estación base 5G |
| UE | User Equipment | Dispositivo del usuario |
| ZMQ | ZeroMQ | Transporte utilizado para intercambiar muestras IQ |
| IQ | In-phase / Quadrature | Representación digital de una señal compleja |
| NAS | Non-Access Stratum | Señalización entre UE y Core |
| NGAP | NG Application Protocol | Señalización N2 entre gNB y AMF |
| SCTP | Stream Control Transmission Protocol | Transporte utilizado por NGAP |
| GTP-U | GPRS Tunnelling Protocol User Plane | Túnel utilizado para datos del usuario |
| PFCP | Packet Forwarding Control Protocol | Control entre SMF y UPF |
| MCC | Mobile Country Code | Código de país/dominio de red móvil |
| MNC | Mobile Network Code | Código de operador/red |
| PLMN | Public Land Mobile Network | Identificador MCC + MNC |
| TAC | Tracking Area Code | Identificador de Tracking Area |
| SST | Slice/Service Type | Tipo de Network Slice |
| SD | Slice Differentiator | Diferenciador de un slice |
| S-NSSAI | Single Network Slice Selection Assistance Information | Identificador formado por SST y opcionalmente SD |
| DNN | Data Network Name | Red de datos solicitada por el UE |
| IMSI | International Mobile Subscriber Identity | Identificador del abonado |
| 5QI | 5G QoS Identifier | Identificador de características QoS |
| ARP | Allocation and Retention Priority | Prioridad de asignación y retención QoS |
| ARFCN | Absolute Radio Frequency Channel Number | Número que representa una frecuencia NR |
| BW | Bandwidth | Ancho de banda |
| SCS | Subcarrier Spacing | Separación entre subportadoras |
| PRB | Physical Resource Block | Unidad de asignación de recursos NR |
| PDCCH | Physical Downlink Control Channel | Canal físico de control downlink |
| PDSCH | Physical Downlink Shared Channel | Canal físico de datos downlink |
| PUSCH | Physical Uplink Shared Channel | Canal físico de datos uplink |
| PUCCH | Physical Uplink Control Channel | Canal físico de control uplink |
| PRACH | Physical Random Access Channel | Canal utilizado para acceso aleatorio |
| PBCH | Physical Broadcast Channel | Canal utilizado para información básica de la celda |
| CORESET | Control Resource Set | Recursos donde se transporta PDCCH |
| MCS | Modulation and Coding Scheme | Esquema de modulación y codificación |
| SINR | Signal-to-Interference-plus-Noise Ratio | Relación señal útil frente a interferencia y ruido |
| C-RNTI | Cell Radio Network Temporary Identifier | Identificador temporal del UE en la celda |
| PDU Session | Protocol Data Unit Session | Sesión de conectividad de datos del UE |
| Zero-RF | Zero Radio Frequency | Pruebas sin transmisión RF física |

---

# 30. Referencias

## srsRAN Project

Documentación oficial:

https://docs.srsran.com/projects/project/

Tutorial oficial de srsRAN Project utilizando srsUE y ZeroMQ:

https://docs.srsran.com/projects/project/en/latest/tutorials/source/srsUE/source/

Referencia de configuración del gNB:

https://docs.srsran.com/projects/project/en/latest/user_manuals/source/config_ref.html

Repositorio oficial de srsRAN Project:

https://github.com/srsran/srsRAN_Project

Releases:

https://github.com/srsran/srsRAN_Project/releases

## srsRAN 4G / srsUE

Documentación:

https://docs.srsran.com/projects/4g/

Repositorio:

https://github.com/srsran/srsRAN_4G

Documentación histórica del escenario 5G SA con Open5GS y ZeroMQ:

https://docs.srsran.com/projects/4g/en/latest/app_notes/source/5g_sa_E2E/source/index.html

## Open5GS

Documentación oficial:

https://open5gs.org/open5gs/docs/

Quickstart:

https://open5gs.org/open5gs/docs/guide/01-quickstart/

Repositorio:

https://github.com/open5gs/open5gs

## MongoDB

Documentación oficial:

https://www.mongodb.com/docs/

## 3GPP

Las especificaciones 3GPP son la referencia normativa para la arquitectura y procedimientos 5G.

Portal de especificaciones:

https://www.3gpp.org/specifications

Entre las especificaciones relevantes para etapas posteriores del análisis se encuentran:

- TS 23.501 — arquitectura del sistema 5G.
- TS 23.502 — procedimientos del sistema 5G.
- TS 24.501 — protocolo NAS 5G.
- TS 38.211 — canales físicos y modulación.
- TS 38.212 — multiplexación y codificación.
- TS 38.214 — procedimientos de capa física para datos.
- TS 38.331 — protocolo RRC.

---

# Nota final

Esta rama busca conservar una implementación **reproducible** de la variante basada en srsRAN Project 25.10.

Por esta razón se recomienda no actualizar versiones, parámetros o dependencias de forma arbitraria sin documentar el cambio.

Si se desea experimentar con OCUDU, esos cambios deben mantenerse en:

```text
feature/OCUDU
```

La implementación descrita en este documento debe permanecer en:

```text
feature/srsRAN
```

para que ambas soluciones puedan compararse de manera independiente.