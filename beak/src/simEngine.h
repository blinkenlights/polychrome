#pragma once
#include "engine.h"

namespace beak::sim
{
using Node = juce::AudioProcessorGraph::Node;
class SimulationEngine : public Engine
{
 public:
  SimulationEngine(int virtualOutputs);

  [[nodiscard]] Error configureGraph(Config const &config) override;

 private:
  int m_virtualOutputs;
  juce::HashMap<Node::Ptr, Node::Ptr> m_playerNodeToPanners;
};

}  // namespace beak::sim
