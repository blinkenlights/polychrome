#include "processor.h"

namespace beak
{

/* ---------------------------- panning processor --------------------------- */
/**
 * @brief Construct a new Panning Processor:: Panning Processor object
 *
 * @param inputNum  The input number this panning processor uses
 * @param maxInputs The maximum number of inputs (used to calculate panning position)
 */
PanningProcessor::PanningProcessor(int inputNum, int maxInputs) :
  ProcessorBase(BusesProperties()
                    .withInput("Input", juce::AudioChannelSet::stereo())
                    .withOutput("Output", juce::AudioChannelSet::stereo())),
  m_inputNum(inputNum),
  m_maxInputs(maxInputs)
{
  m_panner.setRule(juce::dsp::PannerRule::squareRoot3dB);
  const double pan = (((double)m_inputNum / m_maxInputs) * 2) - 1;
  m_panner.setPan(pan);
}

/**
 * @brief Destroy the Panning Processor:: Panning Processor object
 *
 */
PanningProcessor::~PanningProcessor() { m_panner.reset(); }

/**
 * @brief Reimplemented to release the panners resources.
 *
 */
void PanningProcessor::releaseResources() { m_panner.reset(); }

/**
 * @brief Reimplemented to reset the panner.
 *
 */
void PanningProcessor::reset() { m_panner.reset(); }

/**
 * @brief Reimplemented to prepare playback with panning.
 *
 * @param sampleRate      The sample rate to use
 * @param samplesPerBlock The expected samples per block
 */
void PanningProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
  juce::dsp::ProcessSpec spec = {sampleRate, static_cast<juce::uint32>(samplesPerBlock), 2};
  m_panner.prepare(spec);
}

/**
 * @brief Reimplemented to do the actual panning.
 *
 * @param buffer Reference to the buffer to write to.
 */
void PanningProcessor::processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &)
{
  juce::dsp::AudioBlock<float> block(buffer);
  juce::dsp::ProcessContextReplacing<float> context(block);
  m_panner.process(context);
}

/**
 * @brief Construct a new Sampler Processor:: Sampler Processor object
 *
 */
SamplerProcessor::SamplerProcessor() :
  ProcessorBase(BusesProperties()
                    .withInput("Input", juce::AudioChannelSet::mono())
                    .withOutput("Output", juce::AudioChannelSet::mono()))
{
  m_formatManager.registerBasicFormats();
}

/**
 * @brief Destroy the Sampler Processor:: Sampler Processor object
 *
 */
SamplerProcessor::~SamplerProcessor() { m_source.releaseResources(); }

/**
 * @brief Reimplemented to prepare playback.
 *
 * @param sampleRate      The sample rate to use.
 * @param samplesPerBlock The expected number of samples per block.
 */
void SamplerProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
  m_source.prepareToPlay(samplesPerBlock, sampleRate);
}

/**
 * @brief Reimplemented to process the block with the mixer source doing the heavy lifting.
 *
 * @param buffer Buffer to write to.
 */
void SamplerProcessor::processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &)
{
  m_source.getNextAudioBlock(juce::AudioSourceChannelInfo(buffer));
}

/**
 * @brief Removes all inputs from the mixer source.
 *
 */
void SamplerProcessor::reset() { m_source.removeAllInputs(); }

/**
 * @brief Releases the resources of the mixer source which will release all input resources.
 *
 */
void SamplerProcessor::releaseResources() { m_source.releaseResources(); }

/**
 * @brief Plays one sample
 *
 * @param file Path to file
 */
void SamplerProcessor::playSample(juce::File const &file)
{
  juce::AudioFormatReader *reader = m_formatManager.createReaderFor(file);
  auto transportSource = new juce::AudioTransportSource();

  transportSource->setSource(new juce::AudioFormatReaderSource(reader, true), 0, nullptr,
                             reader->sampleRate);
  const juce::MessageManagerLock mmLock;
  transportSource->addChangeListener(this);
  transportSource->start();
  m_source.addInputSource(transportSource, true);
}

/**
 * @brief Reimplemented to handle finished sources
 *
 * Only checks for stopped samples.
 *
 * @param emitter   Emitter of the change signal
 */
void SamplerProcessor::changeListenerCallback(juce::ChangeBroadcaster *emitter)
{
  if (auto emitterSource = dynamic_cast<juce::AudioTransportSource *>(emitter))
  {
    if (!emitterSource->isPlaying())
    {
      m_source.removeInputSource(emitterSource);
    }
  }
}
}  // namespace beak
