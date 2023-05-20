#include "processor.h"

/**
 * @brief Construct a new Processor Base:: Processor Base object
 *
 * @param inputs
 * @param outputs
 */
ProcessorBase::ProcessorBase(int inputs, int outputs) :
  AudioProcessor(BusesProperties()
                     .withInput("Input", juce::AudioChannelSet::discreteChannels(inputs))
                     .withOutput("Output", juce::AudioChannelSet::discreteChannels(outputs)))
{
}

/**
 * @brief Construct a new Mono File Player Processor:: Mono File Player
 * Processor object
 *
 * @param file
 */
MonoFilePlayerProcessor::MonoFilePlayerProcessor(
    std::unique_ptr<juce::AudioFormatReaderSource> src) :
  ProcessorBase(1, 1), m_readerSource(std::move(src))
{
  m_source.setSource(m_readerSource.get());
}

/**
 * @brief Construct a new Mono File Player Processor:: Mono File Player
 * Processor object
 *
 * @param file
 */
MonoFilePlayerProcessor::MonoFilePlayerProcessor(std::unique_ptr<juce::MemoryAudioSource> src) :
  ProcessorBase(1, 1), m_readerSource(std::move(src))
{
  m_source.setSource(m_readerSource.get());
}

MonoFilePlayerProcessor::MonoFilePlayerProcessor(juce::File const &file) : ProcessorBase(1, 1)
{
  m_formatManager.registerBasicFormats();

  m_readerSource =
      std::make_unique<juce::AudioFormatReaderSource>(m_formatManager.createReaderFor(file), true);
  m_source.setSource(m_readerSource.get());
}

MonoFilePlayerProcessor::~MonoFilePlayerProcessor() { releaseResources(); }

/**
 * @brief
 *
 */
void MonoFilePlayerProcessor::releaseResources() { m_source.releaseResources(); }

/**
 * @brief
 *
 * @param sampleRate
 * @param samplesPerBlock
 */
void MonoFilePlayerProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
  m_source.prepareToPlay(static_cast<int>(sampleRate), samplesPerBlock);
}

/**
 * @brief
 *
 * @param buffer
 */
void MonoFilePlayerProcessor::processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &)
{
  m_source.getNextAudioBlock(juce::AudioSourceChannelInfo(buffer));
}
