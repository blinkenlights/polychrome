#include <Arduino.h>
#include <NeoPixelBus.h>
#include <Pixel.h>
#include <Pixel_calibrations.h>
#include <Network.h>

EasingMode easing_mode;
uint32_t easing_interval_ms;
bool enable_calibration = false;
NeoGamma<NeoGammaTableMethod> colorGamma;

Pixel::Pixel()
{
	start_color = RgbwColor(0, 0, 0, 0);
	target_color = RgbwColor(0, 0, 0, 0);
	easing_active = false;
}

void Pixel::set_easing_interval(uint32_t interval_ms)
{
	easing_interval_ms = interval_ms;
}

void Pixel::set_easing_mode(EasingMode mode)
{
	easing_mode = mode;
}

void Pixel::set_enable_calibration(bool enable)
{
	enable_calibration = enable;
}

void Pixel::set_color(RgbwColor color)
{
	// we apply gamma correction and calibration at the start so all color operations inside this class are done in the the corrected color space
	if (enable_calibration)
	{
		target_color = RgbwColor(calibration_table_r[color.R], calibration_table_g[color.G], calibration_table_b[color.B], color.W);
	}
	else
	{
		target_color = color;
	}

	start_color = current_color;
	start_time_ms = millis();
	easing_active = true;
}

RgbwColor Pixel::get_display_color()
{
	if (!easing_active)
	{
		return current_color;
	}

	uint32_t elapsed_time = millis() - start_time_ms;

	if (elapsed_time >= easing_interval_ms)
	{
		easing_active = false;
		start_color = target_color;
		current_color = target_color;
		return current_color;
	}

	float ratio = get_easing(float(elapsed_time) / float(easing_interval_ms));
	current_color = RgbwColor::LinearBlend(start_color, target_color, ratio);

	return current_color;
}

float Pixel::get_easing(float value)
{
	switch (easing_mode)
	{
	case EasingMode_EASE_IN_QUAD:
		return ease_in_quad(value);
	case EasingMode_EASE_OUT_QUAD:
		return ease_out_quad(value);
	case EasingMode_EASE_IN_OUT_QUAD:
		return ease_in_out_quad(value);
	case EasingMode_EASE_IN_CUBIC:
		return ease_in_cubic(value);
	case EasingMode_EASE_OUT_CUBIC:
		return ease_out_cubic(value);
	case EasingMode_EASE_IN_OUT_CUBIC:
		return ease_in_out_cubic(value);
	case EasingMode_EASE_IN_QUART:
		return ease_in_quart(value);
	case EasingMode_EASE_OUT_QUART:
		return ease_out_quart(value);
	case EasingMode_EASE_IN_OUT_QUART:
		return ease_in_out_quart(value);
	case EasingMode_EASE_IN_QUINT:
		return ease_in_quint(value);
	case EasingMode_EASE_OUT_QUINT:
		return ease_out_quint(value);
	case EasingMode_EASE_IN_OUT_QUINT:
		return ease_in_out_quint(value);
	case EasingMode_EASE_IN_EXPO:
		return ease_in_expo(value);
	case EasingMode_EASE_OUT_EXPO:
		return ease_out_expo(value);
	case EasingMode_EASE_IN_OUT_EXPO:
		return ease_in_out_expo(value);
	default:
		return linear(value);
	}
}

float Pixel::linear(float t) { return t; }

float Pixel::ease_in_quad(float t) { return t * t; }

float Pixel::ease_out_quad(float t) { return t * (2 - t); }

float Pixel::ease_in_out_quad(float t) { return t < .5 ? 2 * t * t : -1 + (4 - 2 * t) * t; }

float Pixel::ease_in_cubic(float t) { return t * t * t; }

float Pixel::ease_out_cubic(float t) { return (--t) * t * t + 1; }

float Pixel::ease_in_out_cubic(float t) { return t < .5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1; }

float Pixel::ease_in_quart(float t) { return t * t * t * t; }

float Pixel::ease_out_quart(float t) { return 1 - (--t) * t * t * t; }

float Pixel::ease_in_out_quart(float t) { return t < .5 ? 8 * t * t * t * t : 1 - 8 * (--t) * t * t * t; }

float Pixel::ease_in_quint(float t) { return t * t * t * t * t; }

float Pixel::ease_out_quint(float t) { return 1 + (--t) * t * t * t * t; }

float Pixel::ease_in_out_quint(float t) { return t < .5 ? 16 * t * t * t * t * t : 1 + 16 * (--t) * t * t * t * t; }

float Pixel::ease_in_expo(float t) { return t == 0 ? 0 : pow(2, 10 * t - 10); }

float Pixel::ease_out_expo(float t) { return t == 1 ? 1 : 1 - pow(2, -10 * t); }

float Pixel::ease_in_out_expo(float t)
{
	return t == 0 ? 0 : t == 1 ? 1
									: t < 0.5	 ? pow(2, 20 * t - 10) / 2
														 : (2 - pow(2, -20 * t + 10)) / 2;
}