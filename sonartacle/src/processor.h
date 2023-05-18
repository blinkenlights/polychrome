#pragma once
#include <JuceHeader.h>

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

class MonoFilePlayerProcessor : public ProcessorBase
{
 public:
  MonoFilePlayerProcessor(std::unique_ptr<juce::AudioFormatReaderSource> src);
  MonoFilePlayerProcessor(juce::File const &file);

  void prepareToPlay(double sampleRate, int samplesPerBlock) override;

  void processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &) override;

  void reset() override { m_source.stop(); }
  void start() { m_source.start(); }
  bool isPlaying() const { return m_source.isPlaying(); }

  const juce::String getName() const override { return juce::String(m_name); }

  void releaseResources() override;

 private:
  juce::AudioFormatManager m_formatManager;
  std::shared_ptr<juce::AudioFormatReaderSource> m_readerSource;
  juce::AudioTransportSource m_source;
  std::string m_name;
};
