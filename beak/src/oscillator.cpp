#include "oscillator.h"

namespace beak::synth
{

void Oscillator::prepareToPlay(double sampleRate, int samplesPerBlock, int outputChannels)
{
  resetAll();

  juce::dsp::ProcessSpec spec;
  spec.maximumBlockSize = samplesPerBlock;
  spec.sampleRate = sampleRate;
  spec.numChannels = outputChannels;

  prepare(spec);
  m_osc.prepare(spec);
  m_gain.prepare(spec);
}

void Oscillator::setType(const Type oscSelection)
{
  switch (oscSelection)
  {
    // Sine
    case Type::Sine:
      initialise([](float x) { return std::sin(x); });
      break;

    // Saw
    case Type::Saw:
      initialise([](float x) { return x / juce::MathConstants<float>::pi; });
      break;

    // Square
    case Type::Square:
      initialise([](float x) { return x < 0.0f ? -1.0f : 1.0f; });
      break;

    default:
      // You shouldn't be here!
      jassertfalse;
      break;
  }
}

void Oscillator::setGain(const float levelInDecibels) { m_gain.setGainDecibels(levelInDecibels); }

void Oscillator::setFreq(const int midiNoteNumber)
{
  setFrequency(juce::MidiMessage::getMidiNoteInHertz((midiNoteNumber)), true);
}

void Oscillator::renderNextBlock(juce::dsp::AudioBlock<float>& audioBlock)
{
  jassert(audioBlock.getNumSamples() > 0);
  process(juce::dsp::ProcessContextReplacing<float>(audioBlock));
  m_osc.process(juce::dsp::ProcessContextReplacing<float>(audioBlock));
  m_gain.process(juce::dsp::ProcessContextReplacing<float>(audioBlock));
}

float Oscillator::processNextSample(float input)
{
  return m_gain.processSample(processSample(input));
}

void Oscillator::setParams(const Parameters& params)
{
  m_params = params;
  setType(params.type);
  setGain(params.gain);
}

void Oscillator::resetAll()
{
  reset();
  m_osc.reset();
  m_gain.reset();
}
}  // namespace beak::synth
