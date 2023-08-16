#include <Arduino.h>
#include <Network.h>
#include <ETH.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>

#include <schema.pb.h>
#include <pb_decode.h>
#include <pb_encode.h>
#include <Display.h>

#ifdef PANEL_HOSTNAME
String hostname = String(PANEL_HOSTNAME);
#else
String hostname = "blinkenleds-" + String(PANEL_INDEX);
#endif

#define UDP_PORT 1337
#define UDP_BUFFER_SIZE 1500 // This needs to be increased for RGBFrames
uint8_t udp_buffer[UDP_BUFFER_SIZE];
WiFiUDP udp;

static bool eth_connected = false;
static bool ota_up = false;

#define METRICS_INTERVAL 5000
uint32_t framecount = 0;
uint32_t packetcount = 0;
uint32_t last_metrics_send = 0;

bool remote_configured = false;
IPAddress remote_ip;
uint16_t remote_port = 4422;

void udp_setup()
{
  udp.begin(UDP_PORT);
  Serial.println("Listening on UDP port " + String(UDP_PORT));
}

void network_event_callback(WiFiEvent_t event)
{
  switch (event)
  {
  case ARDUINO_EVENT_ETH_START:
    // Serial.println("ETH Started");
    // Serial.println("Setting hostname: " + String(hostname));
    // ETH.setHostname(hostname.c_str());

    break;
  case ARDUINO_EVENT_ETH_CONNECTED:
    Serial.println("ETH Connected");
    break;

  case ARDUINO_EVENT_ETH_GOT_IP6:
    Serial.println("Got IPv6:");
    Serial.println("  Local  : " + String(ETH.localIPv6().toString()));

    static ip6_addr_t addr;
    tcpip_adapter_get_ip6_global(TCPIP_ADAPTER_IF_ETH, &addr);
    Serial.println("  Global : " + String(IPv6Address(addr.addr).toString()));

    break;

  case ARDUINO_EVENT_ETH_GOT_IP:
    Serial.println("Got IPv4:");

    Serial.println("  MAC   : " + String(ETH.macAddress()));
    Serial.println("  IPv4  : " + String(ETH.localIP().toString()));
    Serial.println("  GW    : " + String(ETH.gatewayIP().toString()));
    Serial.println("  SubNet: " + String(ETH.subnetMask().toString()));
    Serial.println("  DNS   : " + String(ETH.dnsIP().toString()));
    Serial.println("  Speed : " + String(ETH.linkSpeed()) + " Mbps");

    udp_setup();
    Network::send_firmware_info();
    eth_connected = true;
    break;
  case ARDUINO_EVENT_ETH_DISCONNECTED:
    Serial.println("ETH Disconnected");
    eth_connected = false;
    break;
  case ARDUINO_EVENT_ETH_STOP:
    Serial.println("ETH Stopped");
    eth_connected = false;
    break;
  default:
    break;
  }
}

void ota_setup()
{

  Serial.println("Setting up OTA");
  Serial.println("Using mDNS hostname: " + hostname);

  ArduinoOTA
      .setHostname(hostname.c_str())
      .setMdnsEnabled(true)
      .onStart([]()
               {
                 String type;
                 if (ArduinoOTA.getCommand() == U_FLASH)
                   type = "sketch";
                 else // U_SPIFFS
                   type = "filesystem";

                 // NOTE: if updating SPIFFS this would be the place to unmount SPIFFS using SPIFFS.end()
                 Serial.println("Start updating " + type); })
      .onEnd([]()
             { Serial.println("\nEnd"); })
      .onProgress([](unsigned int progress, unsigned int total)
                  { 
                    // We run the display loop to prevent flickering
                    Display::loop();
                    Serial.printf("Progress: %u%%\r", (progress / (total / 100))); })
      .onError([](ota_error_t error)
               {
                   Serial.printf("Error[%u]: ", error);
                   if (error == OTA_AUTH_ERROR)
                     Serial.println("Auth Failed");
                   else if (error == OTA_BEGIN_ERROR)
                     Serial.println("Begin Failed");
                   else if (error == OTA_CONNECT_ERROR)
                     Serial.println("Connect Failed");
                   else if (error == OTA_RECEIVE_ERROR)
                     Serial.println("Receive Failed");
                   else if (error == OTA_END_ERROR)
                     Serial.println("End Failed"); });
}

void ota_handle()
{
  if (!ota_up)
  {
    Serial.println("Starting OTA");
    ArduinoOTA.begin();
    ota_up = true;
  }
  ArduinoOTA.handle();
}

void Network::setup()
{
  Serial.println("Ethernet setup.");
  WiFi.onEvent(network_event_callback);

  Serial.println("ETH begin.");
  // from: https://quinled.info/quinled-esp32-ethernet/
  ETH.begin(0, 5, 23, 18, ETH_PHY_LAN8720, ETH_CLOCK_GPIO17_OUT);
  ETH.enableIpV6();

  ota_setup();

  // MDNS
  if (MDNS.begin(hostname.c_str()))
  {
    Serial.println("MDNS started");
    MDNS.addService("blinkenleds", "udp", 1337);
  }
  else
  {
    Serial.println("MDNS");
  }

  Serial.println("Ethernet setup done");
}

void Network::loop()
{
  int bytes;

  framecount++;

  if (eth_connected)
  {
    ota_handle();

    // handle UDP packets
    while (udp.parsePacket())
    {
      if (!remote_configured)
      {
        remote_ip = udp.remoteIP();
        remote_port = udp.remotePort();
        remote_configured = true;
        Serial.println("Got first packet from " + remote_ip.toString() + ":" + String(remote_port));
        send_firmware_info();
      }

      bytes = udp.read(udp_buffer, UDP_BUFFER_SIZE);

      if (bytes > 0)
      {
        packetcount++;
        pb_istream_t stream = pb_istream_from_buffer(udp_buffer, bytes);
        Packet packet = Packet_init_zero;
        bool status = pb_decode(&stream, Packet_fields, &packet);

        if (!status)
        {
          Network::remote_log("Protobuf decoding failed: " + String(PB_GET_ERROR(&stream)));
        }
        else
        {
          // Serial.println("Got valid protobuf. Type: " + String(packet.which_content));
          Display::handle_packet(packet);
        }
      }
    }

    if (millis() - last_metrics_send > METRICS_INTERVAL)
    {
      Network::send_firmware_info();
    }
  }
}

void send_udp_packet(uint16_t length)
{
  if (remote_configured)
  {
    udp.beginPacket(remote_ip, remote_port);
    udp.write(udp_buffer, length);
    udp.endPacket();
  }
}

void Network::remote_log(String message)
{
  if (eth_connected)
  {
    Serial.println("Remote log: " + message);

    FirmwarePacket packet = FirmwarePacket_init_default;
    packet.which_content = FirmwarePacket_remote_log_tag;
    packet.content.remote_log = (RemoteLog)RemoteLog_init_default;
    message.toCharArray(packet.content.remote_log.message, 100);

    pb_ostream_t stream = pb_ostream_from_buffer(udp_buffer, UDP_BUFFER_SIZE);
    pb_encode(&stream, FirmwarePacket_fields, &packet);

    send_udp_packet(stream.bytes_written);
  }
  else
  {
    Serial.println("Remote log (not sent): " + message);
  }
}

void Network::send_firmware_info()
{
  FirmwarePacket packet = FirmwarePacket_init_default;
  packet.which_content = FirmwarePacket_firmware_info_tag;
  packet.content.firmware_info = (FirmwareInfo)FirmwareInfo_init_default;

  String version = String(VERSION);
  version.toCharArray(packet.content.firmware_info.build_time, 20);
  hostname.toCharArray(packet.content.firmware_info.hostname, 20);
  packet.content.firmware_info.panel_index = PANEL_INDEX;
  packet.content.firmware_info.config_phash = Display::get_config_phash();

  packet.content.firmware_info.frames_per_second = framecount * 1000 / (millis() - last_metrics_send);
  framecount = 0;
  packet.content.firmware_info.packets_per_second = packetcount * 1000 / (millis() - last_metrics_send);
  packetcount = 0;

  ETH.macAddress().toCharArray(packet.content.firmware_info.mac, 18);
  ETH.localIP().toString().toCharArray(packet.content.firmware_info.ipv4, 15);
  ETH.localIPv6().toString().toCharArray(packet.content.firmware_info.ipv6_local, 39);

  static ip6_addr_t addr;
  tcpip_adapter_get_ip6_global(TCPIP_ADAPTER_IF_ETH, &addr);
  IPv6Address(addr.addr).toString().toCharArray(packet.content.firmware_info.ipv6_global, 39);

  packet.content.firmware_info.free_heap = ESP.getFreeHeap();
  packet.content.firmware_info.heap_size = ESP.getHeapSize();

  packet.content.firmware_info.uptime = millis();

  pb_ostream_t stream = pb_ostream_from_buffer(udp_buffer, UDP_BUFFER_SIZE);
  pb_encode(&stream, FirmwarePacket_fields, &packet);

  send_udp_packet(stream.bytes_written);

  last_metrics_send = millis();
}
