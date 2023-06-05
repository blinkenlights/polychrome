#include "simEngine.h"

#include <plog/Log.h>

namespace beak::sim
{
/**
 * @brief Construct a new Simulation Engine:: Simulation Engine object
 *
 * @param virtualOutputs  Number of virtual outputs, that will be mapped to stereo.
 */
SimulationEngine::SimulationEngine(int virtualOutputs) : m_virtualOutputs(virtualOutputs)
{
  PLOGI << "Running simulation engine with " << m_virtualOutputs << " virtual outputs" << std::endl;
}

/**
 * @brief Reimplemented to configure the graph.
 *
 * Adds a panner node to every virtual input to map to the physical stereo output.
 *
 * @param config
 * @return Error
 */
Error SimulationEngine::configureGraph(Config const &config)
{
  using AudioGraphIOProcessor = juce::AudioProcessorGraph::AudioGraphIOProcessor;

  juce::AudioIODevice *device = m_deviceManager.getCurrentAudioDevice();
  double const sampleRate = device->getCurrentSampleRate();
  int const samplesPerBlock = device->getCurrentBufferSizeSamples();

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
  for (int i = 0; i < m_virtualOutputs; ++i)
  {
    auto playerNode = m_mainProcessor->addNode(std::make_unique<SamplerProcessor>());
    auto pannerNode =
        m_mainProcessor->addNode(std::make_unique<PanningProcessor>(i, m_virtualOutputs));
    m_mainProcessor->addConnection({{playerNode->nodeID, 0}, {pannerNode->nodeID, 0}});
    m_mainProcessor->addConnection({{playerNode->nodeID, 0}, {pannerNode->nodeID, 1}});

    m_mainProcessor->addConnection({{pannerNode->nodeID, 0}, {m_audioOutputNode->nodeID, 0}});
    m_mainProcessor->addConnection({{pannerNode->nodeID, 1}, {m_audioOutputNode->nodeID, 1}});
    m_playerNodes.push_back(playerNode);
  }
  m_player->setProcessor(m_mainProcessor.get());
  m_deviceManager.addAudioCallback(m_player.get());
  m_mainProcessor->getCallbackLock().exit();

  return Error();
}
}  // namespace beak::sim
