#pragma once
#include <JuceHeader.h>

#include <cassert>

class ProcessorBase : public juce::AudioProcessor
{
 public:
  //==============================================================================
  ProcessorBase(int inputs, int outputs);

  //==============================================================================
  void prepareToPlay(double, int) override {}
  void processBlock(juce::AudioSampleBuffer &, juce::MidiBuffer &) override {}

  //==============================================================================
  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }

  //==============================================================================
  const juce::String getName() const override { return {}; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  double getTailLengthSeconds() const override { return 0; }

  //==============================================================================
  int getNumPrograms() override { return 0; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}

  //==============================================================================
  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

 private:
  //==============================================================================
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ProcessorBase)
};

using NodeID = juce::AudioProcessorGraph::NodeID;

class MonoFilePlayerProcessor : public ProcessorBase
{
 public:
  MonoFilePlayerProcessor(std::unique_ptr<juce::AudioFormatReaderSource> src);

  MonoFilePlayerProcessor(juce::File const &file);
  ~MonoFilePlayerProcessor();

  void prepareToPlay(double sampleRate, int samplesPerBlock) override;

  void processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &) override;

  void reset() override { m_source.stop(); }
  void start() { m_source.start(); }
  void stop() { m_source.stop(); }
  bool isPlaying() const { return m_source.isPlaying() && m_source.hasStreamFinished(); }

  const juce::String getName() const override { return juce::String(m_name); }

  void releaseResources() override;
  void setNodeID(NodeID const &nodeID) { m_nodeID = nodeID; }

 private:
  juce::AudioFormatManager m_formatManager;
  std::shared_ptr<juce::AudioFormatReaderSource> m_readerSource;
  juce::AudioTransportSource m_source;
  std::string m_name;
  NodeID m_nodeID;
};
