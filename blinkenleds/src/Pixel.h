#ifndef __PIXEL_H_INCLUDED__
#define __PIXEL_H_INCLUDED__

#include <schema.pb.h>
#include <NeoPixelBus.h>

class Pixel
{

public:
	Pixel();
	// Set color from regular RGB color space
	void set_color(RgbwColor color);

	// Color with applied easings, gamma correction and calibarion
	RgbwColor get_display_color();

	// Set easing parameters
	static void set_params(uint32_t interval_ms, EasingMode mode, bool disable_corrections);

private:
	int32_t start_time_ms;
	RgbwColor start_color;
	RgbwColor target_color;
	RgbwColor current_color;
	bool easing_active;

	static const uint8_t calibration_table_r[256];
	static const uint8_t calibration_table_g[256];
	static const uint8_t calibration_table_b[256];

	static float get_easing(float value);
	static float linear(float t);
	static float ease_in_quad(float t);
	static float ease_out_quad(float t);
	static float ease_in_out_quad(float t);
	static float ease_in_cubic(float t);
	static float ease_out_cubic(float t);
	static float ease_in_out_cubic(float t);
	static float ease_in_quart(float t);
	static float ease_out_quart(float t);
	static float ease_in_out_quart(float t);
	static float ease_in_quint(float t);
	static float ease_out_quint(float t);
	static float ease_in_out_quint(float t);
	static float ease_in_expo(float t);
	static float ease_out_expo(float t);
	static float ease_in_out_expo(float t);
};

#endif // __PIXEL_H_INCLUDED__
