#pragma once

#include <juce_dsp/juce_dsp.h>

#include "oscillator.h"

namespace beak::synth
{
class Filter : public juce::dsp::StateVariableTPTFilter<float>
{
 public:
  enum class Type
  {
    Lowpass,
    Bandpass,
    Highpass
  };

  struct Parameters
  {
    Parameters() = default;
    Parameters(const Type& _type, float _cutoff, float _resonance) :
      type(_type), cutoff(_cutoff), resonance(_resonance)
    {
    }
    Type type{Type::Lowpass};
    float cutoff{20000};
    float resonance{1};
  };

 public:
  Filter();
  void prepareToPlay(double sampleRate, int samplesPerBlock, int outputChannels);
  void setParams(const Parameters& params);
  void setModulator(const float mod);
  // void processNextBlock(juce::AudioBuffer<float>& buffer);
  float processNextSample(int channel, float inputValue);
  void resetAll();

 private:
  void selectFilterType(const Type type);
  void update();

 private:
  Parameters m_params;
  float m_mod{1.0f};
};
}  // namespace beak::synth
