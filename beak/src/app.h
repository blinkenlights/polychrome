#pragma once

#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_core/juce_core.h>
#include <juce_gui_basics/juce_gui_basics.h>

namespace beak
{

constexpr uint32_t defaultPort = 1337;

class MainApp : public juce::ConsoleApplication, public juce::JUCEApplication, public juce::Thread
{
 public:
  MainApp();
  ~MainApp() override;
  MainApp(const MainApp &) = delete;
  MainApp(MainApp &&) = delete;
  MainApp &operator=(const MainApp &) = delete;
  MainApp &operator=(MainApp &&) = delete;

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
  juce::String m_args;
};
}  // namespace beak
