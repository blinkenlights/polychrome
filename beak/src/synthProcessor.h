#pragma once

#include "filter.h"
#include "processor.h"
#include "synthSound.h"
#include "synthVoice.h"

namespace beak
{

class SynthProcessor : public ProcessorBase, private juce::Timer
{
 public:
  //==============================================================================
  SynthProcessor();
  ~SynthProcessor() override;

  //==============================================================================
  void prepareToPlay(double sampleRate, int samplesPerBlock) override;
  void releaseResources() override;

  void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

 public:
  void setVoiceParams(const synth::Oscillator::Parameters& oscParams,
                      const juce::ADSR::Parameters& adsrParams);
  void setFilterParams(const synth::Filter::Parameters& filterParams,
                       const juce::ADSR::Parameters& adsr);
  void setReverbParams(const juce::Reverb::Parameters& reverbParams);
  void noteOn(int note, int duration);
  void noteOff(int note);
  void timerCallback() override;

 private:
  void updateVoices();
  void updateFilter();
  void updateReverb();

 private:
  static constexpr int m_numVoices{1};
  juce::Synthesiser m_synth;
  synth::Oscillator::Parameters m_oscillatorParams;
  juce::ADSR::Parameters m_adsrParams;
  synth::Filter::Parameters m_filterParams;
  juce::ADSR::Parameters m_filterAdsrParams;
  juce::dsp::Reverb m_reverb;
  juce::Reverb::Parameters m_reverbParams;
  juce::HashMap<int, int, juce::DefaultHashFunctions, juce::CriticalSection> m_noteOffs;
  static constexpr int m_timerIntervalMs{20};
  bool m_isPrepared{false};

  //==============================================================================
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SynthProcessor)
};

}  // namespace beak
