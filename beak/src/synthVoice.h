#pragma once

#include <juce_dsp/juce_dsp.h>

#include "filter.h"
#include "oscillator.h"
#include "synthSound.h"

namespace beak::synth
{
class Voice : public juce::SynthesiserVoice
{
 public:
  bool canPlaySound(juce::SynthesiserSound* sound) override;
  void startNote(int midiNoteNumber, float velocity, juce::SynthesiserSound* sound,
                 int currentPitchWheelPosition) override;
  void stopNote(float velocity, bool allowTailOff) override;
  void controllerMoved([[maybe_unused]] int controllerNumber,
                       [[maybe_unused]] int newControllerValue) override
  {
  }
  void pitchWheelMoved([[maybe_unused]] int newPitchWheelValue) override {}
  void prepareToPlay(double sampleRate, int samplesPerBlock, int outputChannels);
  void renderNextBlock(juce::AudioBuffer<float>& outputBuffer, int startSample,
                       int numSamples) override;

  bool isVoiceActive() const override { return m_adsr.isActive(); }

  Oscillator& getOscillator() { return m_osc; }
  juce::ADSR& getADSR() { return m_adsr; }
  juce::ADSR& getFilterADSR() { return m_filterAdsr; }
  Filter& getFilter() { return m_filter; }

  void reset();

 private:
  Oscillator m_osc;
  Filter m_filter;
  juce::ADSR m_adsr;
  juce::ADSR m_filterAdsr;
  juce::AudioBuffer<float> m_synthBuffer;

  juce::dsp::Gain<float> m_gain;
  bool m_isPrepared{false};
};
}  // namespace beak::synth
