#include <Arduino.h>
#include <Network.h>
#include <ETH.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <cstdio>
#include <mdns.h>

#include <schema.pb.h>
#include <pb_decode.h>
#include <pb_encode.h>
#include <Display.h>
#include <Proximity.h>

#ifdef PANEL_HOSTNAME
String hostname = String(PANEL_HOSTNAME);
#else
String hostname = "blinkenleds-" + String(PANEL_INDEX);
#endif

#define UDP_PORT_BASE 1337
#define UDP_BUFFER_SIZE 4096
#define METRICS_INTERVAL 5000
#define MAX_SENDERS 8

static uint8_t udp_buffer[UDP_BUFFER_SIZE];
static bool eth_connected = false;
static bool ota_up = false;
static uint32_t eth_connected_at = 0;

struct SenderRecord
{
  IPAddress ip;
  uint16_t port;
  uint32_t last_seen_ms;
};

struct BusNetwork
{
  WiFiUDP udp;
  uint16_t listen_port;
  SenderRecord sender_records[MAX_SENDERS];
  int sender_record_count;
  uint32_t last_pixel_packet_ms;
  bool remote_configured;
  IPAddress remote_ip;
  uint16_t remote_port;
  DisplayMode sender_mode;
  uint32_t framecount;
  uint32_t packetcount;
  uint32_t last_metrics_send;
};

static BusNetwork buses[BUS_COUNT];

static bool is_pixel_packet(const Packet &packet)
{
  switch (packet.which_content)
  {
  case Packet_w_frame_tag:
  case Packet_rgb_frame_tag:
  case Packet_rgb_frame_part1_tag:
  case Packet_rgb_frame_part2_tag:
    return true;
  default:
    return false;
  }
}

static void prune_sender_records(BusNetwork &bus, uint32_t now)
{
  int write_index = 0;

  for (int read_index = 0; read_index < bus.sender_record_count; read_index++)
  {
    if (now - bus.sender_records[read_index].last_seen_ms <= METRICS_INTERVAL)
    {
      bus.sender_records[write_index++] = bus.sender_records[read_index];
    }
  }

  bus.sender_record_count = write_index;
}

static void record_pixel_sender(BusNetwork &bus, IPAddress ip, uint16_t port)
{
  uint32_t now = millis();
  bus.last_pixel_packet_ms = now;

  for (int i = 0; i < bus.sender_record_count; i++)
  {
    if (bus.sender_records[i].ip == ip && bus.sender_records[i].port == port)
    {
      bus.sender_records[i].last_seen_ms = now;
      return;
    }
  }

  if (bus.sender_record_count < MAX_SENDERS)
  {
    bus.sender_records[bus.sender_record_count].ip = ip;
    bus.sender_records[bus.sender_record_count].port = port;
    bus.sender_records[bus.sender_record_count].last_seen_ms = now;
    bus.sender_record_count++;
  }
}

static void update_sender_state(int bus_index)
{
  BusNetwork &bus = buses[bus_index];
  uint32_t now = millis();
  prune_sender_records(bus, now);

  DisplayMode new_mode;

  if (bus.sender_record_count > 1)
  {
    new_mode = DisplayMode::Conflict;
    bus.remote_configured = false;
  }
  else if (bus.sender_record_count == 1)
  {
    new_mode = DisplayMode::Normal;
    bus.remote_ip = bus.sender_records[0].ip;
    bus.remote_port = bus.sender_records[0].port;
    bus.remote_configured = true;
  }
  else
  {
    bool boot_grace =
        bus.last_pixel_packet_ms == 0 &&
        eth_connected_at > 0 &&
        (now - eth_connected_at) < METRICS_INTERVAL;

    if (boot_grace)
    {
      new_mode = DisplayMode::Normal;
      bus.remote_configured = false;
    }
    else
    {
      new_mode = DisplayMode::Idle;
      bus.remote_configured = false;
    }
  }

  if (new_mode != bus.sender_mode)
  {
    switch (new_mode)
    {
    case DisplayMode::Conflict:
      Serial.println("Bus " + String(bus_index) + ": multiple pixel senders in 5s window");
      break;
    case DisplayMode::Idle:
      Serial.println("Bus " + String(bus_index) + ": no pixel sender in 5s window");
      break;
    case DisplayMode::Normal:
      if (bus.remote_configured)
      {
        Serial.println(
            "Bus " + String(bus_index) + ": single pixel sender " + bus.remote_ip.toString() +
            ":" + String(bus.remote_port));
      }
      break;
    }

    Display::set_display_mode(bus_index, new_mode);
    bus.sender_mode = new_mode;
  }
}

static void reset_metrics_counters(BusNetwork &bus)
{
  bus.framecount = 0;
  bus.packetcount = 0;
  bus.last_metrics_send = millis();
}

static void send_udp_packet(BusNetwork &bus, uint16_t length)
{
  if (bus.remote_configured)
  {
    bus.udp.beginPacket(bus.remote_ip, bus.remote_port);
    bus.udp.write(udp_buffer, length);
    bus.udp.endPacket();
  }
}

static bool mdns_services_advertised = false;

// TXT value pointers must remain valid after mdns_service_add returns.
static char mdns_mac[18];
static char mdns_panel_index[8];
static char mdns_bus_index[BUS_COUNT][4];
static char mdns_instance[BUS_COUNT][32];

static void advertise_bus_services()
{
  if (mdns_services_advertised)
  {
    return;
  }

  ETH.macAddress().toCharArray(mdns_mac, sizeof(mdns_mac));
  snprintf(mdns_panel_index, sizeof(mdns_panel_index), "%d", PANEL_INDEX);

  for (int bus_index = 0; bus_index < BUS_COUNT; bus_index++)
  {
    BusNetwork &bus = buses[bus_index];
    snprintf(mdns_bus_index[bus_index], sizeof(mdns_bus_index[bus_index]), "%d", bus_index);
#ifdef DUAL_UDP_PORTS
    snprintf(mdns_instance[bus_index], sizeof(mdns_instance[bus_index]), "Pixie port %d", bus_index + 1);
#else
    snprintf(mdns_instance[bus_index], sizeof(mdns_instance[bus_index]), "Polychrome port %d", bus_index + 1);
#endif

    mdns_txt_item_t txt[] = {
        {"txt_version", "1"},
        {"mac", mdns_mac},
        {"bus", mdns_bus_index[bus_index]},
        {"panel_index", mdns_panel_index},
        {"matrix", "8x8"},
        {"wire_map", "serpentine_horizontal_bottom_left"},
        {"max_px", "64"},
        {"fw", FIRMWARE_VERSION},
    };

    esp_err_t err = mdns_service_add(
        mdns_instance[bus_index],
        "_blinkenleds",
        "_udp",
        bus.listen_port,
        txt,
        8);

    if (err != ESP_OK)
    {
      Serial.printf("mDNS service add failed for bus %d: %d\n", bus_index, (int)err);
    }
    else
    {
      Serial.printf(
          "mDNS: %s._blinkenleds._udp on port %u\n",
          mdns_instance[bus_index],
          bus.listen_port);
    }
  }

  mdns_services_advertised = true;
}

static void udp_setup()
{
  for (int bus = 0; bus < BUS_COUNT; bus++)
  {
    buses[bus].listen_port = UDP_PORT_BASE + bus;
    buses[bus].sender_record_count = 0;
    buses[bus].last_pixel_packet_ms = 0;
    buses[bus].remote_configured = false;
    buses[bus].remote_port = 4422;
    buses[bus].sender_mode = DisplayMode::Normal;
    buses[bus].framecount = 0;
    buses[bus].packetcount = 0;
    buses[bus].last_metrics_send = millis();

    buses[bus].udp.begin(buses[bus].listen_port);
    Serial.println("Listening on UDP port " + String(buses[bus].listen_port));
  }
}

void network_event_callback(WiFiEvent_t event)
{
  switch (event)
  {
  case ARDUINO_EVENT_ETH_START:
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
    eth_connected_at = millis();
    eth_connected = true;
    advertise_bus_services();
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
                 else
                   type = "filesystem";

                 Serial.println("Start updating " + type); })
      .onEnd([]()
             { Serial.println("\nEnd"); })
      .onProgress([](unsigned int progress, unsigned int total)
                  {
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
  ETH.begin(0, 5, 23, 18, ETH_PHY_LAN8720, ETH_CLOCK_GPIO17_OUT);
  ETH.enableIpV6();

  ota_setup();

  if (MDNS.begin(hostname.c_str()))
  {
    Serial.println("MDNS started");
  }
  else
  {
    Serial.println("MDNS start failed");
  }

  Serial.println("Ethernet setup done");
}

static void handle_bus_udp(int bus_index)
{
  BusNetwork &bus = buses[bus_index];
  int bytes;

  while (bus.udp.parsePacket())
  {
    IPAddress sender_ip = bus.udp.remoteIP();
    uint16_t sender_port = bus.udp.remotePort();

    bytes = bus.udp.read(udp_buffer, UDP_BUFFER_SIZE);

    if (bytes > 0)
    {
      bus.packetcount++;
      pb_istream_t stream = pb_istream_from_buffer(udp_buffer, bytes);
      Packet packet = Packet_init_zero;
      bool status = pb_decode(&stream, Packet_fields, &packet);

      if (!status)
      {
        Network::remote_log("Protobuf decoding failed: " + String(PB_GET_ERROR(&stream)));
      }
      else if (is_pixel_packet(packet))
      {
        bool was_idle = bus.sender_mode == DisplayMode::Idle;

        record_pixel_sender(bus, sender_ip, sender_port);
        update_sender_state(bus_index);

        if (was_idle && bus.sender_mode == DisplayMode::Normal && bus.remote_configured)
        {
          Network::send_firmware_info(bus_index);
        }

        if (bus.sender_mode == DisplayMode::Normal && bus.remote_configured)
        {
          Display::handle_packet(bus_index, packet);
        }
      }
      else
      {
        Display::handle_packet(bus_index, packet);
      }
    }
  }
}

void Network::loop()
{
  if (eth_connected)
  {
    ota_handle();

    for (int bus = 0; bus < BUS_COUNT; bus++)
    {
      buses[bus].framecount++;
      handle_bus_udp(bus);
      update_sender_state(bus);

      if (millis() - buses[bus].last_metrics_send > METRICS_INTERVAL)
      {
        if (buses[bus].sender_mode == DisplayMode::Normal && buses[bus].remote_configured)
        {
          Network::send_firmware_info(bus);
        }
        else
        {
          reset_metrics_counters(buses[bus]);
        }
      }
    }
  }
}

void Network::remote_log(String message)
{
  if (eth_connected)
  {
    Serial.println("Remote log: " + message);

    // Prefer bus 0 if configured; otherwise first configured bus
    int bus_index = -1;
    for (int bus = 0; bus < BUS_COUNT; bus++)
    {
      if (buses[bus].remote_configured)
      {
        bus_index = bus;
        if (bus == 0)
        {
          break;
        }
      }
    }

    if (bus_index < 0)
    {
      Serial.println("Remote log (not sent - no configured sender)");
      return;
    }

    FirmwarePacket packet = FirmwarePacket_init_default;
    packet.which_content = FirmwarePacket_remote_log_tag;
    packet.content.remote_log = (RemoteLog)RemoteLog_init_default;
    message.toCharArray(packet.content.remote_log.message, 100);

    pb_ostream_t stream = pb_ostream_from_buffer(udp_buffer, UDP_BUFFER_SIZE);
    pb_encode(&stream, FirmwarePacket_fields, &packet);

    send_udp_packet(buses[bus_index], stream.bytes_written);
  }
  else
  {
    Serial.println("Remote log (not sent): " + message);
  }
}

void Network::send_firmware_info(int bus_index)
{
  if (bus_index < 0 || bus_index >= BUS_COUNT)
  {
    return;
  }

  BusNetwork &bus = buses[bus_index];

  FirmwarePacket packet = FirmwarePacket_init_default;
  packet.which_content = FirmwarePacket_firmware_info_tag;
  packet.content.firmware_info = (FirmwareInfo)FirmwareInfo_init_default;

  snprintf(
      packet.content.firmware_info.build_time,
      sizeof(packet.content.firmware_info.build_time),
      "%s (%s)",
      FIRMWARE_VERSION,
      BUILD_DATE);
  hostname.toCharArray(packet.content.firmware_info.hostname, 20);
  packet.content.firmware_info.panel_index = PANEL_INDEX;
  packet.content.firmware_info.config_phash = Display::get_config_phash(bus_index);

  uint32_t elapsed = millis() - bus.last_metrics_send;
  if (elapsed == 0)
  {
    elapsed = 1;
  }
  packet.content.firmware_info.frames_per_second = bus.framecount * 1000 / elapsed;
  bus.framecount = 0;
  packet.content.firmware_info.packets_per_second = bus.packetcount * 1000 / elapsed;
  bus.packetcount = 0;
  packet.content.firmware_info.proximity_readings_per_second =
      bus_index == 0 ? Proximity::getReadingsPerSecond() : 0;

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

  send_udp_packet(bus, stream.bytes_written);
  bus.last_metrics_send = millis();
}

void Network::send_proximity_event(uint32_t sensor_index, float distance)
{
  // Proximity is device-global; reply on bus 0 when configured
  BusNetwork &bus = buses[0];
  if (!bus.remote_configured)
  {
    return;
  }

  FirmwarePacket packet = FirmwarePacket_init_default;
  packet.which_content = FirmwarePacket_proximity_event_tag;
  packet.content.proximity_event = (ProximityEvent)ProximityEvent_init_default;

  packet.content.proximity_event.panel_index = PANEL_INDEX;
  packet.content.proximity_event.sensor_index = sensor_index;
  packet.content.proximity_event.distance_mm = distance;

  pb_ostream_t stream = pb_ostream_from_buffer(udp_buffer, UDP_BUFFER_SIZE);
  pb_encode(&stream, FirmwarePacket_fields, &packet);

  send_udp_packet(bus, stream.bytes_written);
}
