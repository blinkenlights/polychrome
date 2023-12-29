# Calibration Script

Reads the output (*.cal) from a DisplayCal calibration and converts it to header file with lookup tables for the firmware.


# Howto run a calibration

1. Start DisplayCal and choose `Web @ localhost` as Display
2. Start the `Octopus.Apps.Calibrator` app. It will read the required values from DisplayCal and render them on the pixel.
  * You might need to adjust the app to select the right pixel for calibration.
3. In DisplayCal start the calibration, make sure "Interactive Display Adjustment" is enabled
  * Use the gamma 2.2 Curve, it has shown the best results.
  * Other settings on "As Measured"
  * Very high calibration speed is good enough
4. Start the initial adjustments with "Start measurement"
  * Adjust the red/green/blue correction ratios in `Octopus.Apps.Calibrator` until the colors are at the right levels
  * The color levels are much more important than the right brightness.
5. Go on "stop measurement" and "Continue to Calibration"
  * This will take 30-60 min
6. Copy the resulting .cal file into this directory (mac: ~Library/Application\ Support/DisplayCAL/storage/)
7. Transfer the r,g,b corrections values from 4) to the `convert.exs` script
8. Exectue the script with the filename as argument. `./convert.exs $filename.exs`
9. Copy the rendered `Pixel_corrections.h` into the firmware.