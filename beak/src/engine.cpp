#include "engine.h"

#include "processor.h"
#include "synthProcessor.h"

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
  using AudioGraphIOProcessor = juce::AudioProcessorGraph::AudioGraphIOProcessor;

  juce::AudioIODevice *device = m_deviceManager.getCurrentAudioDevice();
  const double sampleRate = device->getCurrentSampleRate();
  const int samplesPerBlock = device->getCurrentBufferSizeSamples();

  m_mainProcessor->getCallbackLock().enter();
  juce::MessageManagerLock mmLock;

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
  for (int i = 0; i < config.outputs(); ++i)
  {
    auto playerNode = m_mainProcessor->addNode(std::make_unique<SamplerProcessor>());
    m_mainProcessor->addConnection({{playerNode->nodeID, 0}, {m_audioOutputNode->nodeID, i}});
    m_playerNodes.push_back(playerNode);
    auto synthNode = m_mainProcessor->addNode(std::make_unique<SynthProcessor>());
    m_mainProcessor->addConnection({{synthNode->nodeID, 0}, {m_audioOutputNode->nodeID, i}});
    m_synthNodes.push_back(synthNode);
  }
  m_player->setProcessor(m_mainProcessor.get());
  m_deviceManager.addAudioCallback(m_player.get());
  m_mainProcessor->getCallbackLock().exit();
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
  channel = std::min(channel, 10);
  channel = std::max(channel, 1);
  auto playerNode = m_playerNodes.at(channel - 1);
  if (auto proc = dynamic_cast<SamplerProcessor *>(playerNode->getProcessor()))
  {
    proc->playSample(file);
  }
  else
  {
    err = Error("not a SamplerProcessor");
  }
  return err;
}

Error Engine::stopPlayback(int channel)
{
  Error err;
  channel = std::min(channel, 10);
  channel = std::max(channel, 1);
  auto playerNode = m_playerNodes.at(channel - 1);
  if (auto proc = dynamic_cast<SamplerProcessor *>(playerNode->getProcessor()))
  {
    proc->stopPlayback();
  }
  else
  {
    err = Error("not a SamplerProcessor");
  }
  return err;
}

Error Engine::playSynth(const juce::MidiMessage &msg, int maxDurationMs)
{
  Error err;
  int channel = msg.getChannel();
  const int note = msg.getNoteNumber();
  channel = std::min(channel, 10);
  channel = std::max(channel, 1);

  auto synthNode = m_synthNodes.at(channel - 1);
  if (auto proc = dynamic_cast<SynthProcessor *>(synthNode->getProcessor()))
  {
    if (msg.isNoteOn())
    {
      proc->noteOn(note, maxDurationMs);
    }
    else if (msg.isNoteOff())
    {
      proc->noteOff(note);
    }
  }
  return err;
}

Error Engine::configureSynth(int channel, synth::Oscillator::Parameters &osc,
                             const juce::ADSR::Parameters &adsr,
                             const synth::Filter::Parameters &filter,
                             const juce::ADSR::Parameters &filterAdsr)
{
  channel = std::min(channel, 10);
  channel = std::max(channel, 1);
  auto synthNode = m_synthNodes.at(channel - 1);
  if (auto proc = dynamic_cast<SynthProcessor *>(synthNode->getProcessor()))
  {
    proc->setVoiceParams(osc, adsr);
    proc->setFilterParams(filter, filterAdsr);
  }
  return Error{};
}
}  // namespace beak
