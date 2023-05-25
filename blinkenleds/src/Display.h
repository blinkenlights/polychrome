#ifndef __DISPLAY_H_INCLUDED__
#define __DISPLAY_H_INCLUDED__

#include <Pixel.h>
#include <NeoPixelBus.h>
#include <schema.pb.h>

class Display
{
public:
  static void setup();
  static void loop();
  static void handle_packet(Packet packet);
  static RgbwColor color_from_palette(Frame_palette_t palette, uint8_t index);
  static RgbwColor color_from_palette(WFrame_palette_t palette, uint8_t index);
  static uint32_t get_config_phash();

private:
  static void render_test_frame();
  static uint32_t map_index(uint32_t index);
};

#endif // __DISPLAY_H_INCLUDED__
