#pragma once
#include <JuceHeader.h>

#include <memory>

#include "error.h"

using AudioGraphIOProcessor = juce::AudioProcessorGraph::AudioGraphIOProcessor;
using Node = juce::AudioProcessorGraph::Node;
using NodeID = juce::AudioProcessorGraph::NodeID;
using Connection = juce::AudioProcessorGraph::Connection;

class Engine
{
 public:
  Engine(std::shared_ptr<juce::AudioDeviceManager> devMngr,
         juce::String const &deviceName = "", int outputs = 2);

  ~Engine();

 public:
  [[nodiscard]] Error initialize();
  [[nodiscard]] Error playSound(std::shared_ptr<juce::AudioFormatReaderSource> src,
                                int channel);
  [[nodiscard]] Error playSound(const juce::File &file, int channel);

 private:
  [[nodiscard]] Error initializeDeviceManager();
  [[nodiscard]] Error initializeEngine();

 private:
  std::shared_ptr<juce::AudioDeviceManager> m_deviceManager;
  std::unique_ptr<juce::AudioProcessorGraph> m_mainProcessor;  // needs to be pointer?
  std::unique_ptr<juce::AudioProcessorPlayer> m_player;
  int m_outputs;
  int m_sampleRate;
  juce::String m_deviceName;

  Node::Ptr audioOutputNode;
};
