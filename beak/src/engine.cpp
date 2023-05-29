#include "engine.h"

#include "processor.h"

/**
 * @brief Construct a new Multi Channel Sampler:: Multi Channel Sampler object
 *
 * @param devMngr pointer to the device manager
 * @param deviceName name of the device we want to use
 * @param outputs number of outputs
 */
Engine::Engine() :
  m_mainProcessor(new juce::AudioProcessorGraph()), m_player(new juce::AudioProcessorPlayer(true))
{
}

Engine::~Engine()
{
  m_deviceManager.removeAudioCallback(m_player.get());
  m_mainProcessor->releaseResources();
  m_mainProcessor->clear();
}

/**
 * @brief Initializes the audio engine which is a AudioGraph.
 *
 */
Error Engine::configureGraph(Config const &config)
{
  std::scoped_lock<std::mutex> lock(mut);
  juce::AudioIODevice *device = m_deviceManager.getCurrentAudioDevice();
  uint32_t sampleRate = device->getCurrentSampleRate();
  int samplesPerBlock = device->getCurrentBufferSizeSamples();

  if (!m_mainProcessor->enableAllBuses()) return Error("could not enable buses");
  m_mainProcessor->setPlayConfigDetails(config.inputs(), config.outputs(), sampleRate,
                                        samplesPerBlock);
  m_mainProcessor->prepareToPlay(sampleRate, samplesPerBlock);

  m_mainProcessor->clear();
  audioOutputNode = m_mainProcessor->addNode(
      std::make_unique<AudioGraphIOProcessor>(AudioGraphIOProcessor::audioOutputNode));
  if (!audioOutputNode) return Error("could not add output node");
  m_player->setProcessor(m_mainProcessor.get());
  m_deviceManager.addAudioCallback(m_player.get());
  return Error();
}

/**
 * @brief Initializes the device manager with number of outputs and sample rate.
 *
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
 */
Error Engine::configure(Config const &config)
{
  if (auto err = configureDeviceManager(config)) return err;
  if (auto err = configureGraph(config)) return err;
  return Error();
}

/**
 * @brief Plays back a single file
 *
 * @param file
 * @param channel
 */
Error Engine::playSound(std::unique_ptr<juce::MemoryAudioSource> src, int channel,
                        juce::String const &name)
{
  Error err;
  std::scoped_lock<std::mutex> lock(mut);
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
 * @brief Plays back a single file
 *
 * @param file
 * @param channel
 */
Error Engine::playSound(std::unique_ptr<AudioFormatReaderSource> src, int channel,
                        juce::String const &name)
{
  Error err;
  std::scoped_lock<std::mutex> lock(mut);
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
 * @brief Plays back a single file
 *
 * @param file
 * @param channel
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

void Engine::changeListenerCallback(ChangeBroadcaster *source)
{
  if (source)
    if (auto proc = dynamic_cast<MonoFilePlayerProcessor *>(source))
    {
      std::scoped_lock<std::mutex> lock(mut);
      m_mainProcessor->removeNode(proc->getNodeID(), juce::AudioProcessorGraph::UpdateKind::async);
    }
}
