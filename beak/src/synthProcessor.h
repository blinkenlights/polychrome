#pragma once

#include "filter.h"
#include "processor.h"
#include "synthSound.h"
#include "synthVoice.h"

namespace beak
{
class SynthProcessor : public ProcessorBase, public juce::HighResolutionTimer
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
  void hiResTimerCallback() override;

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
  std::unordered_map<int, int> m_noteOffs;
  static constexpr int m_timerIntervalMs{20};

  juce::CriticalSection m_lock;
  bool m_isPrepared{false};

  //==============================================================================
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SynthProcessor)
};

}  // namespace beak
