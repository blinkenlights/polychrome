#include <Arduino.h>
#include <Display.h>
#include <NeoPixelBus.h>
#include <Pixel.h>
#include <Network.h>
#include <schema.pb.h>

#define WIDTH 8
#define HEIGHT 8
#define PIXEL_COUNT (WIDTH * HEIGHT)
#define DATA_PIN_0 16
#define DATA_PIN_1 3

#ifdef SKIP_LEDS
NeoPixelBus<NeoWrgbTm1814Feature, NeoTm1814Method> strip0(PIXEL_COUNT * 2, DATA_PIN_0);
#if BUS_COUNT > 1
NeoPixelBus<NeoWrgbTm1814Feature, NeoTm1814Method> strip1(PIXEL_COUNT * 2, DATA_PIN_1);
#endif
#else
NeoPixelBus<NeoWrgbTm1814Feature, NeoTm1814Method> strip0(PIXEL_COUNT, DATA_PIN_0);
#if BUS_COUNT > 1
NeoPixelBus<NeoWrgbTm1814Feature, NeoTm1814Method> strip1(PIXEL_COUNT, DATA_PIN_1);
#endif
#endif

static NeoPixelBus<NeoWrgbTm1814Feature, NeoTm1814Method> *strips[BUS_COUNT] = {
    &strip0,
#if BUS_COUNT > 1
    &strip1,
#endif
};

static Pixel pixels[BUS_COUNT][PIXEL_COUNT];
static DisplayMode display_modes[BUS_COUNT];
static bool show_test_frame[BUS_COUNT];
static uint32_t config_phash[BUS_COUNT];
static uint8_t luminances[BUS_COUNT];
static bool enable_wframe_red = false;

int Display::bus_count()
{
  return BUS_COUNT;
}

void Display::setup()
{
  for (int bus = 0; bus < BUS_COUNT; bus++)
  {
    display_modes[bus] = DisplayMode::Normal;
    show_test_frame[bus] = true;
    config_phash[bus] = 0;
    luminances[bus] = 255;

    strips[bus]->Begin();
    strips[bus]->SetPixelSettings(NeoTm1814Settings(225, 225, 225, 225));

    for (int i = 0; i < PIXEL_COUNT; i++)
    {
      pixels[bus][i].set_color(RgbwColor(0, 0, 0, 0));
    }

    render_test_frame(bus);
    strips[bus]->Dirty();
    strips[bus]->Show();
  }
}

void Display::loop()
{
  for (int bus = 0; bus < BUS_COUNT; bus++)
  {
    switch (display_modes[bus])
    {
    case DisplayMode::Conflict:
      render_conflict_red(bus);
      break;

    case DisplayMode::Idle:
      render_idle_grey(bus);
      break;

    case DisplayMode::Normal:
      if (show_test_frame[bus])
      {
        render_test_frame(bus);
      }
      else
      {
        for (int i = 0; i < PIXEL_COUNT; i++)
        {
          strips[bus]->SetPixelColor(map_index(i), pixels[bus][i].get_display_color().Dim(luminances[bus]));
        }
      }
      break;
    }

    strips[bus]->Dirty();
    strips[bus]->Show();
  }
}

void Display::set_display_mode(int bus_index, DisplayMode mode)
{
  if (bus_index >= 0 && bus_index < BUS_COUNT)
  {
    display_modes[bus_index] = mode;
  }
}

DisplayMode Display::get_display_mode(int bus_index)
{
  if (bus_index >= 0 && bus_index < BUS_COUNT)
  {
    return display_modes[bus_index];
  }
  return DisplayMode::Idle;
}

void Display::set_enable_wframe_red(bool enable)
{
  enable_wframe_red = enable;
}

bool Display::get_enable_wframe_red()
{
  return enable_wframe_red;
}

uint8_t calculate_r_for_wframe(uint8_t w_value)
{
  const uint8_t max_w = 255;
  const uint8_t max_r = 63;

  if (w_value == 0)
  {
    return 0;
  }

  float ratio = (float)(max_w - w_value) / max_w;
  return (uint8_t)(max_r * ratio * ratio);
}

static void apply_rgb_frame(int bus_index, RGBFrame_data_t data, uint16_t first_pixel, uint16_t last_pixel, bool keep_w)
{
  RgbwColor color;
  for (int i = first_pixel; i <= last_pixel; i++)
  {
    color.R = data.bytes[i * 3];
    color.G = data.bytes[i * 3 + 1];
    color.B = data.bytes[i * 3 + 2];

    if (keep_w)
    {
      RgbwColor original = pixels[bus_index][i - first_pixel].get_original_color();
      color.W = original.W;
      if (enable_wframe_red)
      {
        uint8_t w_r = calculate_r_for_wframe(color.W);
        uint16_t screen_red = color.R + w_r - (color.R * w_r / 255);
        color.R = min(255, (int)screen_red);
      }
    }
    else
    {
      color.W = 0;
    }

    pixels[bus_index][i - first_pixel].set_color(color);
  }
}

static void apply_w_frame(int bus_index, WFrame_data_t data, uint16_t first_pixel, uint16_t last_pixel, bool keep_rgb)
{
  RgbwColor color;
  for (int i = first_pixel; i <= last_pixel; i++)
  {
    uint8_t w = data.bytes[i];

    if (keep_rgb)
    {
      RgbwColor original = pixels[bus_index][i - first_pixel].get_original_color();
      if (enable_wframe_red)
      {
        uint8_t w_r = calculate_r_for_wframe(w);
        uint16_t screen_red = original.R + w_r - (original.R * w_r / 255);
        color.R = min(255, (int)screen_red);
      }
      else
      {
        color.R = original.R;
      }
      color.G = original.G;
      color.B = original.B;
    }
    else
    {
      if (enable_wframe_red)
      {
        color.R = calculate_r_for_wframe(w);
      }
      else
      {
        color.R = 0;
      }
      color.G = 0;
      color.B = 0;
    }

    color.W = w;
    pixels[bus_index][i - first_pixel].set_color(color);
  }
}

void Display::handle_packet(int bus_index, Packet packet)
{
  if (bus_index < 0 || bus_index >= BUS_COUNT)
  {
    return;
  }

  uint16_t first_pixel;
  uint16_t last_pixel;

  switch (packet.which_content)
  {
  case Packet_firmware_config_tag:
    show_test_frame[bus_index] = packet.content.firmware_config.show_test_frame;
    config_phash[bus_index] = packet.content.firmware_config.config_phash;
    Pixel::set_easing_mode(EasingMode(packet.content.firmware_config.easing_mode));
    Pixel::set_enable_calibration(packet.content.firmware_config.enable_calibration);
    luminances[bus_index] = packet.content.firmware_config.luminance;
    break;

  case Packet_w_frame_tag:
    first_pixel = PIXEL_COUNT * (PANEL_INDEX - 1);
    last_pixel = first_pixel + PIXEL_COUNT - 1;
    apply_w_frame(bus_index, packet.content.w_frame.data, first_pixel, last_pixel, packet.content.w_frame.keep_rgb);
    Pixel::set_easing_interval(packet.content.w_frame.easing_interval);
    break;

  case Packet_rgb_frame_tag:
    first_pixel = PIXEL_COUNT * (PANEL_INDEX - 1);
    last_pixel = first_pixel + PIXEL_COUNT - 1;
    apply_rgb_frame(bus_index, packet.content.rgb_frame.data, first_pixel, last_pixel, packet.content.rgb_frame.keep_w);
    Pixel::set_easing_interval(packet.content.rgb_frame.easing_interval);
    break;

  case Packet_rgb_frame_part1_tag:
    if (PANEL_INDEX <= 5)
    {
      first_pixel = PIXEL_COUNT * (PANEL_INDEX - 1);
      last_pixel = first_pixel + PIXEL_COUNT - 1;
      apply_rgb_frame(bus_index, packet.content.rgb_frame_part1.data, first_pixel, last_pixel, packet.content.rgb_frame_part1.keep_w);
      Pixel::set_easing_interval(packet.content.rgb_frame_part1.easing_interval);
    }
    break;

  case Packet_rgb_frame_part2_tag:
    if (PANEL_INDEX > 5)
    {
      first_pixel = PIXEL_COUNT * (PANEL_INDEX - 6);
      last_pixel = first_pixel + PIXEL_COUNT - 1;
      apply_rgb_frame(bus_index, packet.content.rgb_frame_part2.data, first_pixel, last_pixel, packet.content.rgb_frame_part2.keep_w);
      Pixel::set_easing_interval(packet.content.rgb_frame_part2.easing_interval);
    }
    break;

  default:
    break;
  }
}

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
  return mapped_index * 2;
#else
  return mapped_index;
#endif
}

void Display::render_test_frame(int bus_index)
{
  for (int i = 0; i < PIXEL_COUNT; i++)
  {
    RgbwColor color = HsbColor(float(i) / float(PIXEL_COUNT), 1, 1);
    strips[bus_index]->SetPixelColor(map_index(i), color);
  }
}

void Display::render_idle_grey(int bus_index)
{
  const uint8_t w = 26;
  const uint8_t r = enable_wframe_red ? calculate_r_for_wframe(w) : 0;
  RgbwColor color(r, 0, 0, w);

  for (int i = 0; i < PIXEL_COUNT; i++)
  {
    strips[bus_index]->SetPixelColor(map_index(i), color);
  }
}

void Display::render_conflict_red(int bus_index)
{
  bool on = (millis() / 1000) % 2 == 0;
  RgbwColor color = on ? RgbwColor(255, 0, 0, 0) : RgbwColor(0, 0, 0, 0);

  for (int i = 0; i < PIXEL_COUNT; i++)
  {
    strips[bus_index]->SetPixelColor(map_index(i), color);
  }
}

uint32_t Display::get_config_phash(int bus_index)
{
  if (bus_index >= 0 && bus_index < BUS_COUNT)
  {
    return config_phash[bus_index];
  }
  return 0;
}
