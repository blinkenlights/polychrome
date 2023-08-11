#pragma once

#include <juce_dsp/juce_dsp.h>

namespace beak::synth
{
class Oscillator : public juce::dsp::Oscillator<float>
{
 public:
  enum class Type
  {
    Sine,
    Saw,
    Square
  };

  struct Parameters
  {
    Parameters() = default;
    Parameters(const Type& _type, float _gain) : type(_type), gain(_gain) {}
    Type type{Type::Square};
    float gain{1.0f};
  };

 public:
  void prepareToPlay(double sampleRate, int samplesPerBlock, int outputChannels);
  void setType(const Type oscSelection);
  void setGain(const float levelInDecibels);
  void setFreq(const int midiNoteNumber);
  void renderNextBlock(juce::dsp::AudioBlock<float>& audioBlock);
  float processNextSample(float input);
  void setParams(const Parameters& params);
  Parameters getParams() { return m_params; }
  void resetAll();

 private:
  Parameters m_params;
  juce::dsp::Gain<float> m_gain;
  juce::dsp::Oscillator<float> m_osc;
};
}  // namespace beak::synth
