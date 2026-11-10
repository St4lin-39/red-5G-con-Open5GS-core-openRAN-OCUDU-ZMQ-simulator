
# Red 5G SA distribuida con Open5GS + OCUDU + srsUE (Fase 2)

## Descripción del proyecto

Este proyecto implementa una red **5G Standalone (SA)** mediante Open5GS como núcleo de red (5G Core), OCUDU como estación base (gNB) y srsUE como equipo de usuario simulado.

En la **fase 2** se implementó y validó una arquitectura distribuida utilizando dos computadores Ubuntu conectados físicamente mediante Ethernet.

- **Computador de David:** ejecuta Open5GS Core y proporciona acceso a Internet.
- **Computador de Luis:** ejecuta OCUDU gNB y srsUE mediante una interfaz de radio simulada con ZeroMQ (ZMQ).

Se verificaron el registro del UE, la autenticación, el establecimiento de sesión PDU, la señalización N2, el transporte N3 y la conectividad del UE a Internet.

> Las pruebas descritas corresponden al montaje funcional realizado previamente. La arquitectura utiliza radio simulada, sin SDR ni SIM física.

---

## 1. Diferencias entre fase 1 y fase 2

| Característica | Fase 1 | Fase 2 |
|---|---|---|
| Arquitectura | Local | Distribuida |
| Computadores | Un equipo por implementación | Dos equipos conectados por Ethernet |
| Core Open5GS | Local al gNB | Remoto, en el computador de David |
| gNB | srsRAN u OCUDU, según implementación | OCUDU en el computador de Luis |
| UE | Simulado localmente | srsUE con ZMQ en Luis |
| Dirección AMF | Loopback, por ejemplo 127.0.0.5 | 10.53.1.2 |
| Dirección UPF N3 | Local | 10.53.1.2 |
| N2 | Comunicación local | SCTP/NGAP entre computadores |
| N3 | Comunicación local | GTP-U/UDP entre computadores |
| Acceso a Internet | Según escenario local | Validado mediante NAT en David |

En la fase 1 se comprobó el funcionamiento individual de las implementaciones. En la fase 2 se integraron componentes distribuidos mediante una red Ethernet real.

La comunicación entre OCUDU y srsUE continúa utilizando ZMQ localmente en el computador de Luis.

---

## 2. Arquitectura implementada

```text
          COMPUTADOR LUIS (PROMETHEUS)
          IP Ethernet: 10.53.1.1/24

          +------------------------+
          |       srsUE            |
          |    UE simulado         |
          |                        |
          |    Namespace ue1       |
          |    IP: 10.45.0.2       |
          +-----------+------------+
                      |
                  ZeroMQ
              TX/RX 2000/2001
                      |
          +-----------v------------+
          |       OCUDU gNB        |
          |                        |
          | PLMN: 00101            |
          | TAC: 7                 |
          | SST: 1                 |
          +-----------+------------+
                      |
             Ethernet 10.53.1.0/24
                      |
          +-----------v------------+
          |   COMPUTADOR DAVID     |
          |   IP: 10.53.1.2/24     |
          |                        |
          |      Open5GS Core      |
          |                        |
          | AMF <-- N2 / SCTP      |
          | UPF <-- N3 / GTP-U     |
          | SMF / AUSF / UDM       |
          | MongoDB                |
          |                        |
          | ogstun: 10.45.0.1      |
          +-----------+------------+
                      |
                NAT / IPv4
                      |
                 Wi-Fi wlo1
                      |
                  INTERNET
```

### Interfaces utilizadas

| Equipo | Interfaz | Dirección | Función |
|---|---|---|---|
| David | enx68e43b308bfb | 10.53.1.2/24 | Ethernet hacia Luis |
| David | wlo1 | Asignada por Wi-Fi | Salida a Internet |
| David | ogstun | 10.45.0.1/16 | Gateway del UE |
| Luis | enx00e04c3600f8 | 10.53.1.1/24 | Ethernet hacia David |
| Luis | tun_srsue | 10.45.0.2 | Interfaz del UE en namespace ue1 |

### Protocolos utilizados

| Interfaz | Protocolo | Puerto | Función |
|---|---|---|---|
| N2 | NGAP sobre SCTP | 38412 | Señalización gNB-AMF |
| N3 | GTP-U sobre UDP | 2152 | Transporte de datos gNB-UPF |
| Radio simulada | ZeroMQ sobre TCP | 2000 y 2001 | Comunicación OCUDU-srsUE |
| PFCP | PFCP sobre UDP | 8805 | Control SMF-UPF |

---

## 3. Requisitos

### Computador David

- Ubuntu Linux.
- Open5GS Core 2.8.0.
- MongoDB.
- Conexión Ethernet hacia Luis.
- Conexión Wi-Fi con acceso a Internet.
- Permisos de administrador.

### Computador Luis

- Ubuntu Linux.
- OCUDU compilado.
- srsRAN 4G con srsUE.
- Soporte ZeroMQ.
- Conexión Ethernet hacia David.
- Wireshark para análisis de tráfico.

Los componentes deben estar previamente instalados y compilados.

---

## 4. Archivos de configuración

### 4.1 Open5GS Core

Los archivos correspondientes a esta fase están en:

```text
docs/fase-2/config/open5gs/
├── amf.yaml
├── smf.yaml
└── upf.yaml
```

Son copias de las configuraciones utilizadas en el computador de David.

#### AMF

El AMF escucha las conexiones NGAP del gNB remoto:

```yaml
ngap:
  server:
    - address: 10.53.1.2
```

En la fase 1 se utilizaba una dirección local, como `127.0.0.5`.

En esta fase se utiliza `10.53.1.2` para permitir la comunicación desde el computador de Luis.

#### SMF

El SMF gestiona las sesiones PDU y mantiene la comunicación con el UPF mediante direcciones internas.

Parámetros relevantes:

```yaml
pfcp:
  server:
    - address: 127.0.0.4
  client:
    upf:
      - address: 127.0.0.7

session:
  - subnet: 10.45.0.0/16
    gateway: 10.45.0.1
```

No fue necesario cambiar las direcciones internas del SMF, porque los componentes del Core siguen ejecutándose en el mismo computador.

#### UPF

El UPF recibe tráfico GTP-U desde OCUDU mediante la interfaz Ethernet:

```yaml
gtpu:
  server:
    - address: 10.53.1.2

session:
  - subnet: 10.45.0.0/16
    gateway: 10.45.0.1
```

El cambio de la dirección GTP-U permite recibir tráfico N3 desde el gNB remoto.

### 4.2 OCUDU gNB

La configuración del gNB se encuentra en:

```text
config/gnb_zmq.yml
```

La configuración utilizada para ejecutar OCUDU estaba en:

```text
~/ocudu-lab/gnb_zmq.yml
```

Parámetros relevantes:

- AMF remoto: `10.53.1.2`.
- Dirección local del gNB: `10.53.1.1`.
- Puerto NGAP: `38412`.
- PLMN: `00101`.
- TAC: `7`.
- SST: `1`.
- Banda NR: n3.
- Ancho de banda: 10 MHz.

ZeroMQ:

```text
gNB TX: tcp://127.0.0.1:2000
gNB RX: tcp://127.0.0.1:2001
```

### 4.3 srsUE

La configuración funcional del UE se encuentra en el computador de Luis:

```text
~/ocudu-lab/ue_zmq.conf
```

Parámetros principales:

```ini
[gw]
netns = ue1
ip_devname = tun_srsue
ip_netmask = 255.255.255.0
```

El UE utiliza:

- APN/DNN: `internet`.
- Namespace: `ue1`.
- Interfaz: `tun_srsue`.
- ZMQ TX: `tcp://127.0.0.1:2001`.
- ZMQ RX: `tcp://127.0.0.1:2000`.

Los datos USIM deben coincidir con el abonado registrado en Open5GS.

**No publicar las claves reales K, OPc ni otras credenciales del abonado.**

---

## 5. Configuración de red

### 5.1 Conexión Ethernet

Los computadores se conectan físicamente mediante Ethernet.

Direcciones utilizadas:

```text
David: 10.53.1.2/24
Luis:  10.53.1.1/24
```

Verificar las interfaces:

En David:

```bash
ip -4 addr show enx68e43b308bfb
```

En Luis:

```bash
ip -4 addr show enx00e04c3600f8
```

Comprobar conectividad desde Luis:

```bash
ping -c 4 10.53.1.2
```

Las direcciones IP deben estar configuradas en las interfaces correspondientes antes de iniciar el escenario.

### 5.2 Interfaz ogstun

Open5GS utiliza la interfaz `ogstun` para transportar el tráfico IP del UE.

Verificar:

```bash
ip -4 addr show ogstun
```

Configuración utilizada:

```text
Dirección: 10.45.0.1/16
Subred UE: 10.45.0.0/16
```

### 5.3 Habilitar IPv4 forwarding

Para permitir el reenvío de paquetes:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Verificar:

```bash
sysctl net.ipv4.ip_forward
```

Resultado esperado:

```text
net.ipv4.ip_forward = 1
```

### 5.4 Configuración NAT

El tráfico del UE debe salir a Internet mediante la interfaz Wi-Fi de David.

Regla utilizada:

```bash
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 -o wlo1 -j MASQUERADE
```

Antes de agregarla, verificar que no exista:

```bash
sudo iptables -t nat -S POSTROUTING
```

Regla esperada:

```text
-A POSTROUTING -s 10.45.0.0/16 -o wlo1 -j MASQUERADE
```

**No duplicar la regla si ya está configurada.**

La persistencia de estas configuraciones después de reiniciar Ubuntu debe comprobarse por separado.

---

## 6. Procedimiento de ejecución

### Paso 1. Iniciar Open5GS en David

Iniciar MongoDB:

```bash
sudo systemctl start mongod
```

Iniciar Open5GS:

```bash
sudo systemctl start 'open5gs-*'
```

Verificar los servicios:

```bash
systemctl status open5gs-amfd open5gs-smfd open5gs-upfd --no-pager
```

Comprobar que AMF y UPF utilicen las direcciones de la fase 2.

### Paso 2. Detener el Core local de Luis

En esta arquitectura se utiliza únicamente el Core de David.

En Luis:

```bash
sudo systemctl stop 'open5gs-*'
```

Esto evita utilizar accidentalmente el Core local de la fase 1.

### Paso 3. Iniciar OCUDU gNB en Luis

Desde el directorio de compilación que contiene el ejecutable `gnb`:

```bash
sudo ./gnb -c ~/ocudu-lab/gnb_zmq.yml
```

Verificar que OCUDU establezca la conexión NGAP con el AMF remoto.

La conexión N2 utiliza:

```text
Origen:  10.53.1.1
Destino: 10.53.1.2
Puerto:  38412/SCTP
```

### Paso 4. Iniciar srsUE

En otra terminal de Luis:

```bash
cd ~/srsRAN_4G/build/srsue/src
sudo ./srsue ~/ocudu-lab/ue_zmq.conf
```

Durante las pruebas se observó:

- Acceso radio simulado.
- RRC Connected.
- Autenticación del UE.
- Registro en la red.
- Establecimiento de sesión PDU.
- Asignación de IP `10.45.0.2`.

### Paso 5. Configurar la ruta del UE

En las pruebas encontramos que el UE tenía sesión PDU, pero inicialmente no disponía de una ruta predeterminada hacia Internet.

Verificar:

```bash
sudo ip netns exec ue1 ip route
```

Configurar:

```bash
sudo ip netns exec ue1 ip route replace default dev tun_srsue
```

Esta configuración fue necesaria para que el UE pudiera alcanzar Internet.

Si el namespace se recrea al reiniciar srsUE, puede ser necesario aplicar nuevamente el comando.

---

## 7. Pruebas realizadas

### 7.1 Registro del UE

Se verificó el registro exitoso del UE mediante OCUDU y Open5GS.

El gNB estableció comunicación con el AMF remoto y el UE completó los procedimientos de acceso y autenticación.

### 7.2 Sesión PDU

El UE estableció una sesión PDU utilizando el APN `internet`.

Dirección obtenida durante la prueba:

```text
UE:      10.45.0.2
Gateway: 10.45.0.1
```

### 7.3 Conectividad con el gateway

Desde Luis:

```bash
sudo ip netns exec ue1 ping -I tun_srsue -c 4 10.45.0.1
```

Resultado observado:

```text
4 packets transmitted, 4 received
0% packet loss
```

### 7.4 Conectividad a Internet

Desde Luis:

```bash
sudo ip netns exec ue1 ping -I tun_srsue -c 4 8.8.8.8
```

Después de configurar la ruta predeterminada del namespace, la prueba fue exitosa.

El tráfico atravesó:

```text
srsUE
  |
  v
OCUDU gNB
  |
  v
Ethernet
  |
  v
Open5GS UPF
  |
  v
ogstun
  |
  v
NAT / wlo1
  |
  v
Internet
```

---

## 8. Análisis de tráfico con Wireshark

Las pruebas de N2 y N3 se realizaron capturando tráfico en la interfaz Ethernet del computador de Luis.

### 8.1 Interfaz N2: NGAP

Protocolo:

```text
NGAP sobre SCTP
Puerto: 38412
```

Filtros Wireshark:

```text
sctp.port == 38412
```

O:

```text
ngap
```

Mensajes relevantes:

- NGSetupRequest / NGSetupResponse.
- InitialUEMessage.
- UplinkNASTransport.
- DownlinkNASTransport.
- InitialContextSetupRequest / Response.
- PDUSessionResourceSetupRequest / Response.

Los mensajes presentes dependen del momento en que se inicia la captura.

### 8.2 Interfaz N3: GTP-U

Protocolo:

```text
GTP-U sobre UDP
Puerto: 2152
```

Filtros Wireshark:

```text
udp.port == 2152
```

O:

```text
gtp
```

Se observó tráfico GTP-U bidireccional con paquetes ICMP encapsulados entre el UE y la red externa.

### 8.3 Evidencias

Las capturas y evidencias de la fase 2 se encuentran en el repositorio, en la carpeta correspondiente a las evidencias de esta fase.

Se documentaron:

- Señalización N2.
- Tráfico GTP-U de N3.
- Registro del UE.
- Establecimiento de sesión PDU.
- Ping al gateway.
- Conectividad a Internet.

Los archivos de captura deben revisarse antes de publicarse, ya que pueden contener identificadores del abonado o señalización NAS.

---

## 9. Problemas encontrados y soluciones

### Problema 1. AMF configurado para conexiones locales

En la fase 1, el AMF utilizaba una dirección loopback:

```text
127.0.0.5
```

Esto no permitía recibir directamente las conexiones del gNB ubicado en otro computador.

**Solución:**

Configurar el AMF en:

```text
10.53.1.2
```

Y apuntar OCUDU hacia esa dirección.

### Problema 2. UPF configurado para tráfico local

El UPF debía recibir tráfico GTP-U desde el computador de Luis.

**Solución:**

Configurar el servidor GTP-U en:

```text
10.53.1.2
```

Manteniendo la comunicación interna SMF-UPF mediante loopback.

### Problema 3. UE registrado sin acceso a Internet

Inicialmente el UE:

- Se autenticaba correctamente.
- Establecía sesión PDU.
- Recibía la IP `10.45.0.2`.
- Alcanzaba el gateway `10.45.0.1`.
- No recibía correctamente el resultado del ping externo.

Durante el diagnóstico se verificó:

- Tráfico ICMP en `ogstun`.
- Solicitudes y respuestas de Internet en el Core.
- Tráfico GTP-U bidireccional.
- Regla NAT configurada correctamente.

Finalmente se identificó que faltaba la ruta predeterminada dentro del namespace `ue1`.

**Solución:**

```bash
sudo ip netns exec ue1 ip route replace default dev tun_srsue
```

Después de aplicar esta ruta, el ping a `8.8.8.8` funcionó.

---

## 10. Organización del repositorio

La rama utilizada para esta integración es:

```text
feature/fase2
```

Archivos principales:

```text
README.md
config/
    gnb_zmq.yml

docs/
    fase-2/
        config/
            open5gs/
                amf.yaml
                smf.yaml
                upf.yaml
```

Las evidencias de Wireshark y las capturas de terminal se conservan en la carpeta de evidencias de fase 2 del repositorio.

Las configuraciones originales utilizadas durante la ejecución permanecen en:

```text
David:
/etc/open5gs/

Luis:
~/ocudu-lab/
```

El repositorio contiene las configuraciones versionadas, no las instalaciones completas de Open5GS, OCUDU o srsRAN.

---

## 11. Resultados de la fase 2

Se consiguió integrar satisfactoriamente:

1. Open5GS Core ejecutándose en el computador de David.
2. OCUDU gNB ejecutándose en el computador de Luis.
3. srsUE conectado a OCUDU mediante ZeroMQ.
4. Señalización N2 entre computadores.
5. Registro y autenticación del UE.
6. Establecimiento de sesión PDU.
7. Transporte de datos mediante N3/GTP-U.
8. Conectividad del UE con el gateway del Core.
9. Acceso a Internet mediante el UPF y NAT.

## 12. Conclusión

La fase 2 permitió pasar de una arquitectura de laboratorio local a una arquitectura 5G SA distribuida entre dos computadores Ubuntu.

Se comprobó que OCUDU puede comunicarse con un Core Open5GS remoto mediante N2 y N3, manteniendo la simulación radio con ZMQ y permitiendo que el UE establezca una sesión PDU y alcance Internet.

Los resultados demuestran el funcionamiento conjunto del plano de control y del plano de usuario en el escenario probado.

La implementación constituye una base para posteriores pruebas de interoperabilidad y evolución del proyecto.
