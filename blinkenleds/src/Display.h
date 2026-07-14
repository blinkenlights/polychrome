#ifndef __DISPLAY_H_INCLUDED__
#define __DISPLAY_H_INCLUDED__

#include <Pixel.h>
#include <NeoPixelBus.h>
#include <schema.pb.h>

enum class DisplayMode
{
  Normal,
  Idle,
  Conflict,
};

#ifndef BUS_COUNT
#ifdef DUAL_UDP_PORTS
#define BUS_COUNT 2
#else
#define BUS_COUNT 1
#endif
#endif

class Display
{
public:
  static void setup();
  static void loop();
  static void handle_packet(int bus_index, Packet packet);
  static uint32_t get_config_phash(int bus_index);
  static void set_display_mode(int bus_index, DisplayMode mode);
  static DisplayMode get_display_mode(int bus_index);
  static void set_enable_wframe_red(bool enable);
  static bool get_enable_wframe_red();
  static int bus_count();

private:
  static void render_test_frame(int bus_index);
  static void render_idle_grey(int bus_index);
  static void render_conflict_red(int bus_index);
  static uint32_t map_index(uint32_t index);
};

#endif // __DISPLAY_H_INCLUDED__
