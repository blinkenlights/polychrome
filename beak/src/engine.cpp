#include "engine.h"

#include "processor.h"

using AudioGraphIOProcessor = juce::AudioProcessorGraph::AudioGraphIOProcessor;
using Connection = juce::AudioProcessorGraph::Connection;
namespace beak
{
/**
 * @brief Construct a new Multi Channel Sampler:: Multi Channel Sampler object
 *
 */
Engine::Engine() :
  m_mainProcessor(new juce::AudioProcessorGraph()), m_player(new juce::AudioProcessorPlayer(false))
{
}

/**
 * @brief Destroy the Engine:: Engine object
 *
 */
Engine::~Engine()
{
  m_deviceManager.removeAudioCallback(m_player.get());
  m_mainProcessor->releaseResources();
  m_mainProcessor->clear();
}

/**
 * @brief Initialise the audio engine which is a AudioGraph.
 *
 * @param config  Configuration struct
 * @return Error  Custom error type to signal an error
 */
Error Engine::configureGraph(Config const &config)
{
  const juce::ScopedLock lock(m_lock);
  juce::AudioIODevice *device = m_deviceManager.getCurrentAudioDevice();
  double const sampleRate = device->getCurrentSampleRate();
  int const samplesPerBlock = device->getCurrentBufferSizeSamples();

  if (!m_mainProcessor->enableAllBuses())
  {
    return Error("could not enable buses");
  }
  m_mainProcessor->setPlayConfigDetails(config.inputs(), config.outputs(), sampleRate,
                                        samplesPerBlock);
  m_mainProcessor->prepareToPlay(sampleRate, samplesPerBlock);

  m_mainProcessor->clear();
  m_audioOutputNode = m_mainProcessor->addNode(
      std::make_unique<AudioGraphIOProcessor>(AudioGraphIOProcessor::audioOutputNode));
  if (!m_audioOutputNode)
  {
    return Error("could not add output node");
  }
  m_player->setProcessor(m_mainProcessor.get());
  m_deviceManager.addAudioCallback(m_player.get());
  return Error();
}

/**
 * @brief Initializes the device manager with number of outputs and sample rate.
 *
 * @param config  Configuration struct
 * @return Error  Custom error type to signal an error
 */
Error Engine::configureDeviceManager(Config const &config)
{
  if (config.deviceName().isEmpty())
  {
    m_deviceManager.initialiseWithDefaultDevices(config.inputs(), config.outputs());
    return Error();
  }
  auto setup = m_deviceManager.getAudioDeviceSetup();
  setup.inputDeviceName = config.inputs() > 0 ? config.deviceName() : "";
  setup.inputChannels = config.inputs();
  setup.outputDeviceName = config.deviceName();
  setup.outputChannels = config.outputs();
  setup.sampleRate = config.sampleRate();

  auto err =
      m_deviceManager.initialise(config.inputs(), config.outputs(), nullptr, false, "", &setup);
  if (err.isNotEmpty())
  {
    return Error("initializing deviceManager: " + err);
  }
  return Error();
}

/**
 * @brief Initializes the device manager and the audio engine
 *
 * @param config  Configuration struct
 * @return Error  Custom error type to signal an error
 */
Error Engine::configure(Config const &config)
{
  if (auto err = configureDeviceManager(config))
  {
    return err;
  }
  if (auto err = configureGraph(config))
  {
    return err;
  }
  return Error();
}

/**
 * @brief Plays back a sample from a file
 *
 * @param file      The file to be played back
 * @param channel   The channel to play the sample back on
 * @return Error    Custom error to signal a failure
 */
Error Engine::playSound(const juce::File &file, int channel)
{
  Error err;
  const juce::ScopedLock lock(m_lock);
  auto node = m_mainProcessor->addNode(std::make_unique<MonoFilePlayerProcessor>(file));
  auto conn = Connection{{node->nodeID, 0}, {m_audioOutputNode->nodeID, channel - 1}};
  m_mainProcessor->addConnection(conn);
  if (auto proc = dynamic_cast<MonoFilePlayerProcessor *>(node->getProcessor()))
  {
    proc->setNodeID(node->nodeID);
    proc->start();
    const juce::MessageManagerLock mmLock;
    proc->addChangeListener(this);
  }
  else
  {
    err = Error("not a MonoFilePlayerProcessor");
  }
  return err;
}

/**
 * @brief Reimplemented from ChangeListener
 *
 * Called if a node signals taht it is finished playing.
 * It will remove the Processor from the AudioProcessorGraph
 *
 * @param source Emitter source should be castable into a Processor
 */
void Engine::changeListenerCallback(juce::ChangeBroadcaster *source)
{
  if (source)
  {
    if (auto proc = dynamic_cast<MonoFilePlayerProcessor *>(source))
    {
      const juce::ScopedLock lock(m_lock);
      m_mainProcessor->removeNode(proc->getNodeID(), juce::AudioProcessorGraph::UpdateKind::async);
    }
  }
}
}  // namespace beak
