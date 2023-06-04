#include "processor.h"

namespace beak
{

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
 * @brief Construct a new Mono File Player Processor:: Mono File Player Processor object
 *
 * @param file
 */
MonoFilePlayerProcessor::MonoFilePlayerProcessor(juce::File const &file) :
  ProcessorBase(1, 1), m_name(file.getFullPathName())
{
  m_formatManager.registerBasicFormats();
  auto reader = m_formatManager.createReaderFor(file);
  m_source.setSource(new juce::AudioFormatReaderSource(reader, true), 0, nullptr,
                     reader->sampleRate);
  const juce::MessageManagerLock mmLock;
  m_source.addChangeListener(this);
}

/**
 * @brief Destroy the Mono File Player Processor:: Mono File Player Processor object
 *
 */
MonoFilePlayerProcessor::~MonoFilePlayerProcessor() { m_source.releaseResources(); }

void MonoFilePlayerProcessor::reset() { m_source.stop(); }

/**
 * @brief Start the playback
 *
 */
void MonoFilePlayerProcessor::start() { m_source.start(); }

/**
 * @brief Reimplemented to release the resources of the transport source
 *
 */
void MonoFilePlayerProcessor::releaseResources() { m_source.releaseResources(); }

/**
 * @brief
 *
 * @return const juce::String
 */
const juce::String MonoFilePlayerProcessor::getName() const { return m_name; }

/**
 * @brief Reimplemented to prepare playback of the transport source
 *
 * @param sampleRate
 * @param samplesPerBlock
 */
void MonoFilePlayerProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
  m_source.prepareToPlay(samplesPerBlock, sampleRate);
}

/**
 * @brief Callback for AudioProcessorGraph
 *
 * @param buffer buffer to write audio to
 */
void MonoFilePlayerProcessor::processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &)
{
  m_source.getNextAudioBlock(juce::AudioSourceChannelInfo(buffer));
}

/**
 * @brief Callback of the Timer to check if playback has finished
 *
 */
void MonoFilePlayerProcessor::changeListenerCallback(juce::ChangeBroadcaster *)
{
  if (!m_source.isPlaying())
  {
    juce::ChangeBroadcaster::sendChangeMessage();
  }
}

/**
 * @brief Sets the nodeID for this processor as part of an AudioProcessorGraph
 *
 * @param nodeID The id of the node
 */
void MonoFilePlayerProcessor::setNodeID(NodeID const &nodeID) { m_nodeID = nodeID; }

/**
 * @brief Returns the nodeID of this processor as part of an AudioProcessorGraph
 *
 * @return NodeID
 */
NodeID MonoFilePlayerProcessor::getNodeID() const { return m_nodeID; }
}  // namespace beak