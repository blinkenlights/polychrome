#include "synthProcessor.h"

namespace beak
{

SynthProcessor::SynthProcessor() :
  ProcessorBase(BusesProperties()
                    .withInput("Input", juce::AudioChannelSet::stereo(), true)
                    .withOutput("Output", juce::AudioChannelSet::stereo(), true))
{
  m_synth.addSound(new synth::Sound());
  for (int i = 0; i < m_numVoices; i++)
  {
    m_synth.addVoice(new synth::Voice());
  }
  startTimer(m_timerIntervalMs);
}

SynthProcessor::~SynthProcessor() { stopTimer(); }

void SynthProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
  m_synth.setCurrentPlaybackSampleRate(sampleRate);

  for (int i = 0; i < m_synth.getNumVoices(); i++)
  {
    if (synth::Voice* voice = dynamic_cast<synth::Voice*>(m_synth.getVoice(i)))
    {
      voice->prepareToPlay(sampleRate, samplesPerBlock, getTotalNumOutputChannels());
    }
  }

  juce::dsp::ProcessSpec spec;
  spec.maximumBlockSize = samplesPerBlock;
  spec.sampleRate = sampleRate;
  spec.numChannels = getTotalNumOutputChannels();

  m_reverbParams.roomSize = 0.5f;
  m_reverbParams.width = 1.0f;
  m_reverbParams.damping = 0.5f;
  m_reverbParams.freezeMode = 0.0f;
  m_reverbParams.dryLevel = 1.0f;
  m_reverbParams.wetLevel = 0.3f;

  m_reverb.setParameters(m_reverbParams);
  m_isPrepared = true;
}

void SynthProcessor::releaseResources()
{
  // When playback stops, you can use this as an opportunity to free up any
  // spare memory, etc.
}

void SynthProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
  jassert(m_isPrepared);
  juce::ScopedNoDenormals noDenormals;
  auto totalNumInputChannels = getTotalNumInputChannels();
  auto totalNumOutputChannels = getTotalNumOutputChannels();

  for (auto i = totalNumInputChannels; i < totalNumOutputChannels; ++i)
    buffer.clear(i, 0, buffer.getNumSamples());

  updateVoices();
  updateReverb();
  m_synth.renderNextBlock(buffer, midiMessages, 0, buffer.getNumSamples());
  juce::dsp::AudioBlock<float> block{buffer};
  m_reverb.process(juce::dsp::ProcessContextReplacing<float>(block));
}

void SynthProcessor::updateVoices()
{
  for (int i = 0; i < m_synth.getNumVoices(); ++i)
  {
    if (auto voice = dynamic_cast<synth::Voice*>(m_synth.getVoice(i)))
    {
      voice->getOscillator().setParams(m_oscillatorParams);
      voice->getADSR().setParameters(m_adsrParams);
      voice->getFilter().setParams(m_filterParams);
      voice->getFilterADSR().setParameters(m_filterAdsrParams);
    }
  }
}
void SynthProcessor::updateReverb() { m_reverb.setParameters(m_reverbParams); }

void SynthProcessor::setVoiceParams(const synth::Oscillator::Parameters& oscParams,
                                    const juce::ADSR::Parameters& adsrParams)
{
  m_oscillatorParams = oscParams;
  m_adsrParams = adsrParams;
}

void SynthProcessor::setFilterParams(const synth::Filter::Parameters& params,
                                     const juce::ADSR::Parameters& adsrParams)
{
  m_filterParams = params;
  m_filterAdsrParams = adsrParams;
}

void SynthProcessor::setReverbParams(const juce::Reverb::Parameters& params)
{
  m_reverbParams = params;
}

void SynthProcessor::noteOn(int note, int duration = 0)
{
  m_synth.noteOn(1, note, 1.0f);
  const juce::ScopedLock lock(m_lock);
  m_noteOffs[note] = duration;
}

void SynthProcessor::noteOff(int note)
{
  m_synth.noteOff(1, note, 1.0f, false);
  const juce::ScopedLock lock(m_lock);
  if (m_noteOffs.contains(note))
  {
    m_noteOffs.erase(note);
  }
}

void SynthProcessor::hiResTimerCallback()
{
  const juce::ScopedLock lock(m_lock);
  if (m_noteOffs.size() != 0)
  {
    for (auto it = m_noteOffs.cbegin(); it != m_noteOffs.cend(); ++it)
    {
      const int duration = it->second;
      if (duration <= 0)
      {
        noteOff(it->first);
        m_noteOffs.erase(it->first);
      }
      else
      {
        m_noteOffs[it->first] -= m_timerIntervalMs;
      }
    }
  }
}

}  // namespace beak
