#pragma once
#include <JuceHeader.h>

#include <cassert>

class ProcessorBase : public juce::AudioProcessor
{
 public:
  ProcessorBase(int inputs, int outputs);

  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }

  const juce::String getName() const override { return {}; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  double getTailLengthSeconds() const override { return 0; }

  int getNumPrograms() override { return 0; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}

  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

 private:
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ProcessorBase)
};

using NodeID = juce::AudioProcessorGraph::NodeID;

class MonoFilePlayerProcessor : public ProcessorBase,
                                public juce::ChangeBroadcaster,
                                public juce::Timer
{
 public:
  MonoFilePlayerProcessor(juce::File const &file);
  MonoFilePlayerProcessor(std::unique_ptr<juce::PositionableAudioSource> src,
                          juce::String const &name);
  ~MonoFilePlayerProcessor();

  void prepareToPlay(double sampleRate, int samplesPerBlock) override;
  void processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &) override;
  void reset() override;
  void releaseResources() override;
  const juce::String getName() const override;
  void timerCallback() override;

  void start();

  void setNodeID(NodeID const &nodeID);
  NodeID getNodeID() const;

 private:
  juce::AudioFormatManager m_formatManager;
  std::unique_ptr<juce::PositionableAudioSource> m_readerSource;
  juce::AudioTransportSource m_source;
  juce::String m_name;
  NodeID m_nodeID;
};
