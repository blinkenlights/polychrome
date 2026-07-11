#include <Arduino.h>
#include <Display.h>
#include <NeoPixelBus.h>
#include <Pixel.h>
#include <Network.h>
#include <schema.pb.h>

#define WIDTH 8
#define HEIGHT 8
#define PIXEL_COUNT (WIDTH * HEIGHT)
#define DATA_PIN 16

#ifdef SKIP_LEDS
NeoPixelBus<NeoWrgbTm1814Feature, NeoTm1814Method> strip(PIXEL_COUNT * 2, DATA_PIN);
#else
NeoPixelBus<NeoWrgbTm1814Feature, NeoTm1814Method> strip(PIXEL_COUNT, DATA_PIN);
#endif

Pixel pixel[PIXEL_COUNT];
DisplayMode display_mode = DisplayMode::Normal;

// Config defaults
bool show_test_frame = true;
uint32_t config_phash = 0;
uint8_t luminance = 255;

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
  switch (display_mode)
  {
  case DisplayMode::Conflict:
    render_conflict_red();
    break;

  case DisplayMode::Idle:
    render_idle_grey();
    break;

  case DisplayMode::Normal:
    if (show_test_frame)
    {
      render_test_frame();
    }
    else
    {
      for (int i = 0; i < PIXEL_COUNT; i++)
      {
        strip.SetPixelColor(map_index(i), pixel[i].get_display_color().Dim(luminance));
      }
    }
    break;
  }

  strip.Dirty();
  strip.Show();
}

void Display::set_display_mode(DisplayMode mode)
{
  display_mode = mode;
}

DisplayMode Display::get_display_mode()
{
  return display_mode;
}

// Function to calculate R value for a given W value (0-255)
// Based on the formula: r = max_r * ((max_w - w) / max_w)^2
uint8_t calculate_r_for_wframe(uint8_t w_value)
{
  const uint8_t max_w = 255;
  const uint8_t max_r = 63;

  if (w_value == 0)
  {
    return 0;
  }
  else
  {
    float ratio = (float)(max_w - w_value) / max_w;
    return (uint8_t)(max_r * ratio * ratio);
  }
}

void apply_rgb_frame(RGBFrame_data_t data, uint16_t first_pixel, uint16_t last_pixel, bool keep_w)
{
  RgbwColor color;
  for (int i = first_pixel; i <= last_pixel; i++)
  {
    color.R = data.bytes[i * 3];
    color.G = data.bytes[i * 3 + 1];
    color.B = data.bytes[i * 3 + 2];

    if (keep_w)
    {
      RgbwColor original = pixel[i - first_pixel].get_original_color();
      color.W = original.W;
      uint8_t w_r = calculate_r_for_wframe(color.W);
      uint16_t screen_red = color.R + w_r - (color.R * w_r / 255);
      color.R = min(255, (int)screen_red);
    }
    else
    {
      color.W = 0;
    }

    pixel[i - first_pixel].set_color(color);
  }
}

void apply_w_frame(WFrame_data_t data, uint16_t first_pixel, uint16_t last_pixel, bool keep_rgb)
{
  RgbwColor color;
  for (int i = first_pixel; i <= last_pixel; i++)
  {
    uint8_t w = data.bytes[i];
    uint8_t w_r = calculate_r_for_wframe(w);

    if (keep_rgb)
    {
      RgbwColor original = pixel[i - first_pixel].get_original_color();
      uint16_t screen_red = original.R + w_r - (original.R * w_r / 255);

      color.R = min(255, (int)screen_red);
      color.G = original.G;
      color.B = original.B;
    }
    else
    {
      uint8_t r = calculate_r_for_wframe(w);
      color.R = r;
      color.G = 0;
      color.B = 0;
    }

    color.W = w;
    pixel[i - first_pixel].set_color(color);
  }
}

void Display::handle_packet(Packet packet)
{
  uint16_t first_pixel;
  uint16_t last_pixel;

  switch (packet.which_content)
  {
  case Packet_firmware_config_tag:
    show_test_frame = packet.content.firmware_config.show_test_frame;
    config_phash = packet.content.firmware_config.config_phash;
    Pixel::set_easing_mode(EasingMode(packet.content.firmware_config.easing_mode));
    Pixel::set_enable_calibration(packet.content.firmware_config.enable_calibration);
    luminance = packet.content.firmware_config.luminance;

    break;

  case Packet_w_frame_tag:
    first_pixel = PIXEL_COUNT * (PANEL_INDEX - 1);
    last_pixel = first_pixel + PIXEL_COUNT - 1;
    apply_w_frame(packet.content.w_frame.data, first_pixel, last_pixel, packet.content.w_frame.keep_rgb);

    Pixel::set_easing_interval(packet.content.w_frame.easing_interval);

    break;

  case Packet_rgb_frame_tag:
    first_pixel = PIXEL_COUNT * (PANEL_INDEX - 1);
    last_pixel = first_pixel + PIXEL_COUNT - 1;
    apply_rgb_frame(packet.content.rgb_frame.data, first_pixel, last_pixel, packet.content.rgb_frame.keep_w);
    Pixel::set_easing_interval(packet.content.rgb_frame.easing_interval);
    break;

  case Packet_rgb_frame_part1_tag:
    if (PANEL_INDEX <= 5)
    {
      first_pixel = PIXEL_COUNT * (PANEL_INDEX - 1);
      last_pixel = first_pixel + PIXEL_COUNT - 1;
      apply_rgb_frame(packet.content.rgb_frame_part1.data, first_pixel, last_pixel, packet.content.rgb_frame_part1.keep_w);

      Pixel::set_easing_interval(packet.content.rgb_frame_part1.easing_interval);
    }
    break;

  case Packet_rgb_frame_part2_tag:
    if (PANEL_INDEX > 5)
    {
      first_pixel = PIXEL_COUNT * (PANEL_INDEX - 6);
      last_pixel = first_pixel + PIXEL_COUNT - 1;
      apply_rgb_frame(packet.content.rgb_frame_part2.data, first_pixel, last_pixel, packet.content.rgb_frame_part2.keep_w);

      Pixel::set_easing_interval(packet.content.rgb_frame_part2.easing_interval);
    }
    break;

  default:
    // Ignore other packets
    break;
  }
}

// maps the pixel index to the physical layout of the LED strip. The first LED should be bottom left (seen from the front).
uint32_t Display::map_index(uint32_t index)
{
  uint32_t x = index % WIDTH;
  uint32_t y = HEIGHT - 1 - index / WIDTH;

  uint32_t mapped_index;
  if (y % 2 == 0)
  {
    mapped_index = y * WIDTH + x;
  }
  else
  {
    mapped_index = y * WIDTH + (WIDTH - x - 1);
  }

#ifdef SKIP_LEDS
  // Skip every second LED: logical LEDs 0,1,2,3... map to physical LEDs 0,2,4,6...
  return mapped_index * 2;
#else
  // Standard mapping
  return mapped_index;
#endif
}

void Display::render_test_frame()
{
  RgbwColor color;

  for (int i = 0; i < PIXEL_COUNT; i++)
  {
    color = HsbColor(float(i) / float(PIXEL_COUNT), 1, 1);
    strip.SetPixelColor(map_index(i), color);
  }
}

void Display::render_idle_grey()
{
  const uint8_t w = 26; // 10% greyscale W-frame
  const uint8_t r = calculate_r_for_wframe(w);
  RgbwColor color(r, 0, 0, w);

  for (int i = 0; i < PIXEL_COUNT; i++)
  {
    strip.SetPixelColor(map_index(i), color);
  }
}

void Display::render_conflict_red()
{
  RgbwColor color(255, 0, 0, 0);

  for (int i = 0; i < PIXEL_COUNT; i++)
  {
    strip.SetPixelColor(map_index(i), color);
  }
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
