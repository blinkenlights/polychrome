#pragma once
#include <JuceHeader.h>

class MainApp : public juce::ConsoleApplication, public juce::JUCEApplication, public juce::Thread
{
 public:
  MainApp();
  ~MainApp();

  const juce::String getApplicationVersion() override { return "0.0.1"; }
  const juce::String getApplicationName() override { return "beak"; }
  void initialise(const juce::String &args) override;
  void shutdown() override;

  void run() override;

 private:
  static void listCmd(juce::ArgumentList const &args);
  static void playCmd(juce::ArgumentList const &args);
  static void serverCmd(juce::ArgumentList const &args);

 private:
  std::shared_ptr<juce::AudioDeviceManager> m_deviceManager;
  juce::String m_args;
};
