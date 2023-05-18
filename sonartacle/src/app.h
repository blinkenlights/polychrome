#pragma once
#include <JuceHeader.h>

#include "error.h"
#include "processor.h"

using namespace std;

class MainApp : public juce::ConsoleApplication
{
 public:
  MainApp();
  ~MainApp();

  /* -------------------------------- commands -------------------------------
   */
 private:
  [[nodiscard]] Error listDevices() const;
  [[nodiscard]] Error playSound(juce::File const &file, int channel);

  /* --------------------------------- members --------------------------------
   */
 private:
  shared_ptr<juce::AudioDeviceManager> m_deviceManager;
};
