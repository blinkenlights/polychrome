#include <Arduino.h>
#include <Ethernet.h>
#include <ETH.h>
#include <ArduinoOTA.h>
#include <schema.pb.h>
#include <pb_decode.h>
#include <pb_encode.h>
#include <Display.h>

String hostname = "blinkenleds-" + String(PANEL_INDEX);

#define UDP_PORT 1337
#define UDP_BUFFER_SIZE 1500 // This needs to be increased for RGBFrames
uint8_t udp_buffer[UDP_BUFFER_SIZE];
WiFiUDP udp;

static bool eth_connected = false;
static bool ota_up = false;

#define METRICS_INTERVAL 5000
uint32_t framecount = 0;
uint32_t last_metrics_send = 0;

bool remote_configured = false;
IPAddress remote_ip;
uint16_t remote_port = 4422;

void udp_setup()
{
  udp.begin(UDP_PORT);
  Serial.println("Listening on UDP port " + String(UDP_PORT));
}

void wifi_event_callback(WiFiEvent_t event)
{
  switch (event)
  {
  case ARDUINO_EVENT_ETH_START:
    char hostname_c[32];
    hostname.toCharArray(hostname_c, 32);

    Serial.println("ETH Started");
    Serial.println("Setting hostname: " + String(hostname));
    ETH.setHostname(hostname_c);

    break;
  case ARDUINO_EVENT_ETH_CONNECTED:
    Serial.println("ETH Connected");
    break;
  case ARDUINO_EVENT_ETH_GOT_IP:
    Serial.println("DHCP:");

    Serial.println("  MAC   : " + String(ETH.macAddress()));
    Serial.println("  IPv4  : " + String(ETH.localIP().toString()));
    Serial.println("  GW    : " + String(ETH.gatewayIP().toString()));
    Serial.println("  SubNet: " + String(ETH.subnetMask().toString()));
    Serial.println("  DNS   : " + String(ETH.dnsIP().toString()));
    Serial.println("  Name  : " + String(ETH.getHostname()));
    Serial.println("  Speed : " + String(ETH.linkSpeed()) + " Mbps");

    udp_setup();
    Ethernet::send_firmware_info();
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
  ArduinoOTA
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

void Ethernet::setup()
{
  Serial.println("Starting ethernet");
  WiFi.onEvent(wifi_event_callback);

  Serial.println("ETH begin.");
  // from: https://quinled.info/quinled-esp32-ethernet/
  bool res = ETH.begin(0, 5, 23, 18, ETH_PHY_LAN8720, ETH_CLOCK_GPIO17_OUT);

  ota_setup();
  Serial.println("Ethernet setup done");
}

void Ethernet::loop()
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
      }

      bytes = udp.read(udp_buffer, UDP_BUFFER_SIZE);

      if (bytes > 0)
      {
        pb_istream_t stream = pb_istream_from_buffer(udp_buffer, bytes);
        Packet packet = Packet_init_zero;
        bool status = pb_decode(&stream, Packet_fields, &packet);

        if (!status)
        {
          Serial.printf("Protobuf decoding failed: %s\n", PB_GET_ERROR(&stream));
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
      Ethernet::send_firmware_info();
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

void Ethernet::remote_log(String message)
{
  if (eth_connected)
  {
    FirmwarePacket packet = FirmwarePacket_init_default;
    packet.which_content = FirmwarePacket_remote_log_tag;
    packet.content.remote_log = (RemoteLog)RemoteLog_init_default;
    message.toCharArray(packet.content.remote_log.message, 100);

    pb_ostream_t stream = pb_ostream_from_buffer(udp_buffer, UDP_BUFFER_SIZE);
    pb_encode(&stream, FirmwarePacket_fields, &packet);

    send_udp_packet(stream.bytes_written);
  }
}

void Ethernet::send_firmware_info()
{
  FirmwarePacket packet = FirmwarePacket_init_default;
  packet.which_content = FirmwarePacket_firmware_info_tag;
  packet.content.firmware_info = (FirmwareInfo)FirmwareInfo_init_default;

  String version = String(VERSION);
  version.toCharArray(packet.content.firmware_info.build_time, 20);
  hostname.toCharArray(packet.content.firmware_info.hostname, 20);
  packet.content.firmware_info.panel_index = PANEL_INDEX;
  packet.content.firmware_info.config_phash = Display::get_config_phash();

  packet.content.firmware_info.fps = framecount * 1000 / (millis() - last_metrics_send);
  framecount = 0;

  pb_ostream_t stream = pb_ostream_from_buffer(udp_buffer, UDP_BUFFER_SIZE);
  pb_encode(&stream, FirmwarePacket_fields, &packet);

  send_udp_packet(stream.bytes_written);

  last_metrics_send = millis();
}
