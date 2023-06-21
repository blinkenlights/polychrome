#include "synthVoice.h"

#include <plog/Log.h>

namespace beak::synth
{

bool Voice::canPlaySound(juce::SynthesiserSound* sound)
{
  return dynamic_cast<juce::SynthesiserSound*>(sound) != nullptr;
}

void Voice::startNote(int midiNoteNumber, float /*velocity*/, juce::SynthesiserSound* /*sound*/,
                      int /*currentPitchWheelPosition*/)
{
  m_osc.setFreq(midiNoteNumber);
  m_adsr.noteOn();
  m_filterAdsr.noteOn();
}

void Voice::stopNote(float /*velocity*/, bool /*allowTailOff*/)
{
  m_adsr.noteOff();
  m_filterAdsr.noteOff();

  if (!m_adsr.isActive())
  {
    clearCurrentNote();
  }
}

void Voice::prepareToPlay(double sampleRate, int samplesPerBlock, int outputChannels)
{
  reset();

  m_adsr.setSampleRate(sampleRate);
  m_filterAdsr.setSampleRate(sampleRate);

  juce::dsp::ProcessSpec spec;
  spec.maximumBlockSize = samplesPerBlock;
  spec.sampleRate = sampleRate;
  spec.numChannels = outputChannels;

  m_osc.prepareToPlay(sampleRate, samplesPerBlock, outputChannels);
  m_osc.setType(synth::Oscillator::Type::Saw);
  m_filter.prepareToPlay(sampleRate, samplesPerBlock, outputChannels);

  m_gain.prepare(spec);
  m_gain.setGainLinear(0.07f);

  m_isPrepared = true;
}

void Voice::renderNextBlock(juce::AudioBuffer<float>& outputBuffer, int startSample, int numSamples)
{
  jassert(m_isPrepared);

  if (!isVoiceActive())
  {
    return;
  }
  m_synthBuffer.setSize(1, numSamples, false, false, true);

  // we discard the applied envelope, since we don't need it, we are just interested in the next
  // value
  m_filterAdsr.applyEnvelopeToBuffer(m_synthBuffer, 0, m_synthBuffer.getNumSamples());
  m_filter.setModulator(m_filterAdsr.getNextSample());
  m_synthBuffer.clear();

  {
    // scoped pointer to buffer
    auto* buffer = m_synthBuffer.getWritePointer(0, 0);

    for (int s = 0; s < m_synthBuffer.getNumSamples(); ++s)
    {
      buffer[s] = m_osc.processNextSample(buffer[s]);
    }
  }

  juce::dsp::AudioBlock<float> audioBlock{m_synthBuffer};
  m_gain.process(juce::dsp::ProcessContextReplacing<float>(audioBlock));
  m_adsr.applyEnvelopeToBuffer(m_synthBuffer, 0, m_synthBuffer.getNumSamples());

  {
    // scoped pointer to buffer
    auto* buffer = m_synthBuffer.getWritePointer(0, 0);
    for (int s = 0; s < m_synthBuffer.getNumSamples(); ++s)
    {
      buffer[s] = m_filter.processNextSample(0, m_synthBuffer.getSample(0, s));
    }
  }

  outputBuffer.addFrom(0, startSample, m_synthBuffer, 0, 0, numSamples);

  if (!m_adsr.isActive())
  {
    clearCurrentNote();
  }
}

void Voice::reset()
{
  m_gain.reset();
  m_adsr.reset();
}

}  // namespace beak::synth
