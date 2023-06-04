#pragma once
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_audio_processors/juce_audio_processors.h>

#include <cassert>

namespace beak
{
class ProcessorBase : public juce::AudioProcessor
{
 public:
  ProcessorBase(int inputs, int outputs);
  ~ProcessorBase() override {}
  ProcessorBase(ProcessorBase &&) = delete;
  ProcessorBase &operator=(ProcessorBase &&) = delete;

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

constexpr int defaultCleanupInterval = 200;

class MonoFilePlayerProcessor : public ProcessorBase,
                                public juce::ChangeBroadcaster,
                                public juce::ChangeListener
{
 public:
  MonoFilePlayerProcessor(juce::File const &file);
  ~MonoFilePlayerProcessor() override;
  MonoFilePlayerProcessor(MonoFilePlayerProcessor &&) = delete;
  MonoFilePlayerProcessor &operator=(MonoFilePlayerProcessor &&) = delete;

  void prepareToPlay(double sampleRate, int maximumExpectedSamplesPerBlock) override;
  void processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &) override;
  void reset() override;
  void releaseResources() override;
  const juce::String getName() const override;

  void start();

  void setNodeID(NodeID const &nodeID);
  NodeID getNodeID() const;

  void changeListenerCallback(juce::ChangeBroadcaster *source) override;

 private:
  juce::AudioFormatManager m_formatManager;
  juce::AudioTransportSource m_source;
  juce::String m_name;
  NodeID m_nodeID;

 private:
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(MonoFilePlayerProcessor)
};
}  // namespace beak