#include "filter.h"

namespace beak::synth
{

Filter::Filter() { setType(juce::dsp::StateVariableTPTFilterType::lowpass); }

void Filter::setParams(const Parameters& params) { m_params = params; }
void Filter::setModulator(const float mod) { m_mod = mod; }

void Filter::update()
{
  const auto cutoff = juce::jlimit(20.0f, 20000.0f, (m_params.cutoff * m_mod));
  selectFilterType(m_params.type);
  setCutoffFrequency(cutoff);
  setResonance(m_params.resonance);
}

void Filter::prepareToPlay(double sampleRate, int samplesPerBlock, int outputChannels)
{
  resetAll();
  juce::dsp::ProcessSpec spec;
  spec.maximumBlockSize = samplesPerBlock;
  spec.sampleRate = sampleRate;
  spec.numChannels = outputChannels;
  prepare(spec);
}

void Filter::selectFilterType(const Type filterType)
{
  switch (filterType)
  {
    case Type::Lowpass:
      setType(juce::dsp::StateVariableTPTFilterType::lowpass);
      break;
    case Type::Bandpass:
      setType(juce::dsp::StateVariableTPTFilterType::bandpass);
      break;
    case Type::Highpass:
      setType(juce::dsp::StateVariableTPTFilterType::highpass);
      break;
    default:
      setType(juce::dsp::StateVariableTPTFilterType::lowpass);
      break;
  }
}

float Filter::processNextSample(int channel, float inputValue)
{
  update();
  return processSample(channel, inputValue);
}

void Filter::resetAll() { reset(); }
}  // namespace beak::synth
