# RDC Home - Automação Residencial Completa

> **Controle total da sua casa com um toque.**

## Funcionalidades
- Controle de luzes (1 toque)
- Edição de nomes (toque longo)
- Sensores de temperatura e umidade
- Modo noturno automático
- Gráfico de histórico
- Reconexão automática

## Arquitetura
ESP8266/ESP32 → MQTT → Raspberry Pi → Flutter App

## Instalação
1. Clone: `git clone https://github.com/dofordc/rdc-home.git`
2. Configure Mosquitto no Raspberry Pi
3. Carregue os firmwares nos ESPs
4. `flutter run`

## Documentação
- [ESP Firmware](esp/)
- [Flask Server](server/)
- [Flutter App](app/)

## Licença
MIT - Use, modifique, venda!