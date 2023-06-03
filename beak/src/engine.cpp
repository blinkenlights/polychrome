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
  m_mainProcessor(new juce::AudioProcessorGraph()), m_player(new juce::AudioProcessorPlayer(true))
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
  std::scoped_lock<std::mutex> const lock(mut);
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
  audioOutputNode = m_mainProcessor->addNode(
      std::make_unique<AudioGraphIOProcessor>(AudioGraphIOProcessor::audioOutputNode));
  if (!audioOutputNode)
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
 * @brief Play a sound from a MemorySource
 *
 * @param src     AudioSource to be used
 * @param channel Channel to play the sample back on
 * @param name    Name of the sample
 * @return Error  Custom error to signal a failure
 */
Error Engine::playSound(std::unique_ptr<juce::PositionableAudioSource> src, int channel,
                        juce::String const &name)
{
  Error err;
  std::scoped_lock<std::mutex> const lock(mut);
  auto node = m_mainProcessor->addNode(make_unique<MonoFilePlayerProcessor>(std::move(src), name));
  auto conn = Connection{{node->nodeID, 0}, {audioOutputNode->nodeID, channel - 1}};
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
 * @brief Plays back a sample from a file
 *
 * @param file      The file to be played back
 * @param channel   The channel to play the sample back on
 * @return Error    Custom error to signal a failure
 */
Error Engine::playSound(const juce::File &file, int channel)
{
  Error err;
  auto node = m_mainProcessor->addNode(std::make_unique<MonoFilePlayerProcessor>(file));
  auto conn = Connection{{node->nodeID, 0}, {audioOutputNode->nodeID, channel - 1}};
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
      std::scoped_lock<std::mutex> const lock(mut);
      m_mainProcessor->removeNode(proc->getNodeID(), juce::AudioProcessorGraph::UpdateKind::async);
    }
  }
}
}  // namespace beak
