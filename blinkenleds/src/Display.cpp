#include <Arduino.h>
#include <Display.h>
#include <NeoPixelBus.h>
#include <Pixel.h>
#include <Network.h>
#include <schema.pb.h>

#define PIXEL_COUNT 64
#define DATA_PIN 16

NeoPixelBus<NeoWrgbTm1814Feature, NeoTm1814Method> strip(PIXEL_COUNT, DATA_PIN);
Pixel pixel[PIXEL_COUNT];

// Config defaults
bool show_test_frame = true;
uint32_t config_phash = 0;

void Display::setup()
{
  strip.Begin();
  strip.SetPixelSettings(NeoTm1814Settings(225, 225, 225, 225)); // 22.5mA current  rating

  for (int i = 0; i < PIXEL_COUNT; i++)
  {
    pixel[i].set_color(RgbwColor(0, 0, 0, 0));
  }
  render_test_frame();
}

void Display::loop()
{
  if (show_test_frame)
  {
    render_test_frame();
  }
  else
  {
    for (int i = 0; i < PIXEL_COUNT; i++)
    {
      // strip.SetPixelColor(map_index(i), pixel[i].get_display_color());
      strip.SetPixelColor(map_index(i), pixel[i].get_display_color());
    }
  }

  strip.Dirty();
  strip.Show();
}

void Display::handle_packet(Packet packet)
{
  switch (packet.which_content)
  {
  case Packet_firmware_config_tag:
    show_test_frame = packet.content.firmware_config.show_test_frame;
    config_phash = packet.content.firmware_config.config_phash;
    Pixel::set_easing_mode(EasingMode(packet.content.firmware_config.easing_mode));
    Pixel::set_enable_calibration(packet.content.firmware_config.enable_calibration);
    Pixel::set_luminance(packet.content.firmware_config.luminance);

    break;

  case Packet_frame_tag:

    for (int i = 0; i < min(PIXEL_COUNT, int(packet.content.frame.data.size)); i++)
    {
      pixel[i].set_color(color_from_palette(packet.content.frame.palette, packet.content.frame.data.bytes[i]));
    }

    Pixel::set_easing_interval(packet.content.frame.easing_interval);

    break;

  case Packet_w_frame_tag:

    for (int i = 0; i < min(PIXEL_COUNT, int(packet.content.w_frame.data.size)); i++)
    {
      pixel[i].set_color(color_from_palette(packet.content.w_frame.palette, packet.content.w_frame.data.bytes[i]));
    }

    Pixel::set_easing_interval(packet.content.frame.easing_interval);

    break;
  }
}

RgbwColor Display::color_from_palette(Frame_palette_t palette, uint8_t index)
{
  if (index < palette.size / 3)
  {
    uint8_t r = palette.bytes[index * 3];
    uint8_t g = palette.bytes[index * 3 + 1];
    uint8_t b = palette.bytes[index * 3 + 2];

    return RgbwColor(r, g, b, 0);
  }
  else
  {
    return RgbwColor(0, 0, 0, 0);
  }
}

RgbwColor Display::color_from_palette(WFrame_palette_t palette, uint8_t index)
{
  if (index < palette.size / 4)
  {
    uint8_t r = palette.bytes[index * 4];
    uint8_t g = palette.bytes[index * 4 + 1];
    uint8_t b = palette.bytes[index * 4 + 2];
    uint8_t w = palette.bytes[index * 4 + 3];

    return RgbwColor(r, g, b, w);
  }
  else
  {
    return RgbwColor(0, 0, 0, 0);
  }
}

// maps the pixel index to the physical layout of the LED strip. The first LED should be top left.
uint32_t Display::map_index(uint32_t index)
{
  uint32_t converted;
  switch (index / 8)
  {
  case 1:
    converted = 15 - index % 8;
    break;
  case 3:
    converted = 31 - index % 8;
    break;
  case 5:
    converted = 47 - index % 8;
    break;
  case 7:
    converted = 63 - index % 8;
    break;
  default:
    converted = index;
    break;
  }
  return converted;
}

void Display::render_test_frame()
{
  RgbwColor color;

  for (int i = 0; i < PIXEL_COUNT; i++)
  {
    color = HsbColor(float(i) / float(PIXEL_COUNT), 1, 1);
    strip.SetPixelColor(map_index(i), color);
  }

  strip.Dirty();
  strip.Show();
}

uint32_t Display::get_config_phash()
{
  return config_phash;
}

// void Display::render_test_frame()
// {
//   RgbwColor on = RgbwColor(255, 255, 255, 255);
//   RgbwColor off = RgbwColor(0, 0, 0, 0);

//   float brightness;
//   for (int i = 0; i < 8; i++)
//   {
//     EasingMode easing_mode = EasingMode_EASE_IN_OUT_QUAD;
//     switch (i)
//     {
//     case 0:
//       easing_mode = EasingMode_EASE_IN_QUAD;
//       break;
//     case 1:
//       easing_mode = EasingMode_EASE_IN_CUBIC;
//       break;
//     case 2:
//       easing_mode = EasingMode_EASE_IN_QUART;
//       break;
//     case 3:
//       easing_mode = EasingMode_LINEAR;
//       break;
//     case 4:
//       easing_mode = EasingMode_EASE_OUT_QUAD;
//       break;
//     case 5:
//       easing_mode = EasingMode_EASE_OUT_CUBIC;
//       break;
//     case 6:
//       easing_mode = EasingMode_EASE_OUT_QUART;
//       break;
//     case 7:
//       easing_mode = EasingMode_EASE_IN_OUT_CUBIC;
//       break;
//     }
//     for (int j = 0; j < 8; j++)
//     {
//       brightness = Easing::get_easing(easing_mode, float(j) / 8.0);
//       RgbwColor color = RgbwColor::LinearBlend(off, on, brightness);
//       strip.SetPixelColor(map_index(i * 8 + j), color);
//       strip.SetPixelColor(map_index(i * 8 + j), off);
//     }
//   }

//   strip.Dirty();
//   strip.Show();
// }
