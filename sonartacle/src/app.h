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

 private:
  static void listCmd(juce::ArgumentList const &args);
  static void playCmd(juce::ArgumentList const &args);
  static void runCmd(juce::ArgumentList const &args);

 private:
  shared_ptr<juce::AudioDeviceManager> m_deviceManager;
};
