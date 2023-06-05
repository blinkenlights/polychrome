#pragma once
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>

#include <cassert>

namespace beak
{
using NodeID = juce::AudioProcessorGraph::NodeID;

class ProcessorBase : public juce::AudioProcessor
{
 public:
  ProcessorBase(const BusesProperties &ioConfig) : AudioProcessor(ioConfig){};
  ~ProcessorBase() override {}
  ProcessorBase(ProcessorBase &&) = delete;
  ProcessorBase &operator=(ProcessorBase &&) = delete;

  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }

  void setName(juce::String const &name) { m_name = name; }
  const juce::String getName() const override { return m_name; }
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

 protected:
  juce::String m_name;

 private:
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ProcessorBase)
};

class PanningProcessor : public ProcessorBase
{
 public:
  explicit PanningProcessor(int inputNum, int maxInputs);
  ~PanningProcessor() override;
  PanningProcessor(PanningProcessor &&) = delete;
  PanningProcessor &operator=(PanningProcessor &&) = delete;

  void prepareToPlay(double sampleRate, int samplesPerBlock) override;
  void processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &) override;
  void reset() override;
  void releaseResources() override;

 private:
  int m_inputNum;
  int m_maxInputs;
  juce::dsp::Panner<float> m_panner;

 private:
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PanningProcessor)
};

class SamplerProcessor : public ProcessorBase, public juce::ChangeListener
{
 public:
  explicit SamplerProcessor();
  ~SamplerProcessor() override;
  SamplerProcessor(SamplerProcessor &&) = delete;
  SamplerProcessor &operator=(SamplerProcessor &&) = delete;

  void prepareToPlay(double sampleRate, int maximumExpectedSamplesPerBlock) override;
  void processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &) override;
  void reset() override;
  void releaseResources() override;
  void playSample(juce::File const &file);

  void changeListenerCallback(juce::ChangeBroadcaster *source) override;

 protected:
  juce::AudioFormatManager m_formatManager;
  juce::MixerAudioSource m_source;

 private:
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SamplerProcessor)
};

}  // namespace beak
