#pragma once
#include <JuceHeader.h>

#include "error.h"
#include "processor.h"

using AudioGraphIOProcessor = juce::AudioProcessorGraph::AudioGraphIOProcessor;
using Node = juce::AudioProcessorGraph::Node;
using NodeID = juce::AudioProcessorGraph::NodeID;
using Connection = juce::AudioProcessorGraph::Connection;

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

class MultiChannelSampler
{
 public:
  MultiChannelSampler(shared_ptr<juce::AudioDeviceManager> devMngr,
                      juce::String const &deviceName, int outputs);
  MultiChannelSampler(shared_ptr<juce::AudioDeviceManager> devMngr) :
    MultiChannelSampler(devMngr, "MacBook Pro Speakers", 2)
  {
  }

  ~MultiChannelSampler();

 public:
  [[nodiscard]] Error initialize();
  [[nodiscard]] Error playSound(juce::File const &file, int channel);

 private:
  [[nodiscard]] Error initializeDeviceManager();
  [[nodiscard]] Error initializeEngine();

 private:
  shared_ptr<juce::AudioDeviceManager> m_deviceManager;
  unique_ptr<juce::AudioProcessorGraph> m_mainProcessor;  // needs to be pointer?
  unique_ptr<juce::AudioProcessorPlayer> m_player;
  int m_outputs;
  int m_sampleRate;
  juce::String m_deviceName;

  Node::Ptr audioOutputNode;
};
