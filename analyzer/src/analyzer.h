/*
  ==============================================================================

   This file is part of the JUCE tutorials.
   Copyright (c) 2020 - Raw Material Software Limited

   The code included in this file is provided under the terms of the ISC license
   http://www.isc.org/downloads/software-support-policy/isc-license. Permission
   To use, copy, modify, and/or distribute this software for any purpose with or
   without fee is hereby granted provided that the above copyright notice and
   this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" WITHOUT ANY WARRANTY, AND ALL WARRANTIES,
   WHETHER EXPRESSED OR IMPLIED, INCLUDING MERCHANTABILITY AND FITNESS FOR
   PURPOSE, ARE DISCLAIMED.

  ==============================================================================
*/

/*******************************************************************************
 The block below describes the properties of this PIP. A PIP is a short snippet
 of code that can be read by the Projucer and used to generate a JUCE project.

 BEGIN_JUCE_PIP_METADATA

 name:             AudioProcessorGraphTutorial
 version:          1.0.0
 vendor:           JUCE
 website:          http://juce.com
 description:      Explores the audio processor graph.

 dependencies:     juce_audio_basics, juce_audio_devices, juce_audio_formats,
                   juce_audio_plugin_client, juce_audio_processors,
                   juce_audio_utils, juce_core, juce_data_structures, juce_dsp,
                   juce_events, juce_graphics, juce_gui_basics, juce_gui_extra
 exporters:        xcode_mac, vs2019, linux_make

 type:             AudioProcessor
 mainClass:        TutorialProcessor

 useLocalCopy:     1

 END_JUCE_PIP_METADATA

*******************************************************************************/

#pragma once
#include <plog/Log.h>
#include <schema.pb.h>

//==============================================================================
class ProcessorBase : public juce::AudioProcessor
{
 public:
  //==============================================================================
  ProcessorBase() :
    AudioProcessor(BusesProperties()
                       .withInput("Input", juce::AudioChannelSet::stereo())
                       .withOutput("Output", juce::AudioChannelSet::stereo()))
  {
  }

  //==============================================================================
  void prepareToPlay(double, int) override {}
  void releaseResources() override {}
  void processBlock(juce::AudioSampleBuffer&, juce::MidiBuffer&) override {}

  //==============================================================================
  juce::AudioProcessorEditor* createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }

  //==============================================================================
  const juce::String getName() const override { return {}; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  double getTailLengthSeconds() const override { return 0; }

  //==============================================================================
  int getNumPrograms() override { return 0; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String&) override {}

  //==============================================================================
  void getStateInformation(juce::MemoryBlock&) override {}
  void setStateInformation(const void*, int) override {}

 private:
  //==============================================================================
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ProcessorBase)
};

//==============================================================================
class FilterProcessor : public ProcessorBase
{
 public:
  enum class Type
  {
    low,
    mid,
    high
  };

 public:
  explicit FilterProcessor(Type type, float freq) : m_type(type), m_frequency(freq) {}

  void prepareToPlay(double sampleRate, int samplesPerBlock) override
  {
    switch (m_type)
    {
      case Type::low:
        *filter.state = *juce::dsp::IIR::Coefficients<float>::makeLowPass(sampleRate, m_frequency);
        break;
      case Type::mid:
        *filter.state = *juce::dsp::IIR::Coefficients<float>::makeBandPass(sampleRate, m_frequency);
        break;
      case Type::high:
        *filter.state = *juce::dsp::IIR::Coefficients<float>::makeHighPass(sampleRate, m_frequency);
        break;
    }

    juce::dsp::ProcessSpec spec{sampleRate, static_cast<juce::uint32>(samplesPerBlock), 2};
    filter.prepare(spec);
  }

  void processBlock(juce::AudioSampleBuffer& buffer, juce::MidiBuffer&) override
  {
    juce::dsp::AudioBlock<float> block(buffer);
    juce::dsp::ProcessContextReplacing<float> context(block);
    filter.process(context);
    const float rmsLeft = buffer.getRMSLevel(0, 0, buffer.getNumSamples());
    const float rmsRight = buffer.getRMSLevel(1, 0, buffer.getNumSamples());
    // m_rms = (rmsLeft + rmsRight) / 2;
    m_rms = rmsLeft;
    const float a = 0.7;
    m_rms = a * m_rms + (1 - a) * m_lastValue;
    m_lastValue = m_rms;
  }

  void reset() override { filter.reset(); }

  const juce::String getName() const override { return "Filter"; }

  float getRMS() { return m_rms; }
  Type getType() { return m_type; }

 private:
  juce::String typeToString(Type t)
  {
    switch (t)
    {
      case Type::low:
        return "low";
      case Type::mid:
        return "mid";
      case Type::high:
        return "high";
    }
  }

 private:
  Type m_type;
  float m_frequency;
  float m_rms;

  float m_lastValue;

  juce::dsp::ProcessorDuplicator<juce::dsp::IIR::Filter<float>, juce::dsp::IIR::Coefficients<float>>
      filter;
};

//==============================================================================
class TutorialProcessor : public juce::AudioProcessor, public Timer
{
 public:
  //==============================================================================
  using AudioGraphIOProcessor = juce::AudioProcessorGraph::AudioGraphIOProcessor;
  using Node = juce::AudioProcessorGraph::Node;

  //==============================================================================
  TutorialProcessor() :
    AudioProcessor(BusesProperties()
                       .withInput("Input", juce::AudioChannelSet::stereo(), true)
                       .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
    mainProcessor(new juce::AudioProcessorGraph()),
    m_socket(true)
  {
  }

  //==============================================================================
  bool isBusesLayoutSupported(const BusesLayout& layouts) const override
  {
    if (layouts.getMainInputChannelSet() == juce::AudioChannelSet::disabled() ||
        layouts.getMainOutputChannelSet() == juce::AudioChannelSet::disabled())
      return false;

    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
      return false;

    return layouts.getMainInputChannelSet() == layouts.getMainOutputChannelSet();
  }

  //==============================================================================
  void prepareToPlay(double sampleRate, int samplesPerBlock) override
  {
    mainProcessor->setPlayConfigDetails(getMainBusNumInputChannels(), getMainBusNumOutputChannels(),
                                        sampleRate, samplesPerBlock);

    mainProcessor->prepareToPlay(sampleRate, samplesPerBlock);

    initialiseGraph();
    startTimerHz(60);
  }

  void releaseResources() override { mainProcessor->releaseResources(); }

  void processBlock(juce::AudioSampleBuffer& buffer, juce::MidiBuffer& midiMessages) override
  {
    for (int i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
      buffer.clear(i, 0, buffer.getNumSamples());

    mainProcessor->processBlock(buffer, midiMessages);
  }

  //==============================================================================
  juce::AudioProcessorEditor* createEditor() override
  {
    return new juce::GenericAudioProcessorEditor(*this);
  }
  bool hasEditor() const override { return true; }

  //==============================================================================
  const juce::String getName() const override { return "Graph Tutorial"; }
  bool acceptsMidi() const override { return true; }
  bool producesMidi() const override { return true; }
  double getTailLengthSeconds() const override { return 0; }

  //==============================================================================
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String&) override {}

  //==============================================================================
  void getStateInformation(juce::MemoryBlock&) override {}
  void setStateInformation(const void*, int) override {}

  //==============================================================================
  void timerCallback() override
  {
    SoundToLightControlEvent* event = new SoundToLightControlEvent;
    if (auto filter = dynamic_cast<FilterProcessor*>(lowFilter->getProcessor()))
    {
      event->set_bass(filter->getRMS());
    }
    if (auto filter = dynamic_cast<FilterProcessor*>(midFilter->getProcessor()))
    {
      event->set_mid(filter->getRMS());
    }
    if (auto filter = dynamic_cast<FilterProcessor*>(highFilter->getProcessor()))
    {
      event->set_high(filter->getRMS());
    }
    Packet protoPacket;
    protoPacket.set_allocated_sound_to_light_control_event(event);
    int size = 0;
    std::string msg = protoPacket.SerializePartialAsString();
    m_socket.write("127.0.0.1", 4423, msg.c_str(), msg.length());
  }

 private:
  //==============================================================================
  void initialiseGraph()
  {
    mainProcessor->clear();

    audioInputNode = mainProcessor->addNode(
        std::make_unique<AudioGraphIOProcessor>(AudioGraphIOProcessor::audioInputNode));
    audioOutputNode = mainProcessor->addNode(
        std::make_unique<AudioGraphIOProcessor>(AudioGraphIOProcessor::audioOutputNode));

    lowFilter = mainProcessor->addNode(
        std::make_unique<FilterProcessor>(FilterProcessor::Type::low, 80.0f));
    midFilter = mainProcessor->addNode(
        std::make_unique<FilterProcessor>(FilterProcessor::Type::mid, 1000.0f));
    highFilter = mainProcessor->addNode(
        std::make_unique<FilterProcessor>(FilterProcessor::Type::high, 8000.0f));

    connectAudioNodes();
  }

  void connectAudioNodes()
  {
    for (int channel = 0; channel < 2; ++channel)
    {
      mainProcessor->addConnection(
          {{audioInputNode->nodeID, channel}, {audioOutputNode->nodeID, channel}});
      mainProcessor->addConnection(
          {{audioInputNode->nodeID, channel}, {lowFilter->nodeID, channel}});
      mainProcessor->addConnection(
          {{audioInputNode->nodeID, channel}, {midFilter->nodeID, channel}});
      mainProcessor->addConnection(
          {{audioInputNode->nodeID, channel}, {highFilter->nodeID, channel}});
    }
  }

  //==============================================================================

  std::unique_ptr<juce::AudioProcessorGraph> mainProcessor;

  Node::Ptr audioInputNode;
  Node::Ptr audioOutputNode;
  Node::Ptr midiInputNode;
  Node::Ptr midiOutputNode;

  Node::Ptr lowFilter;
  Node::Ptr midFilter;
  Node::Ptr highFilter;

  DatagramSocket m_socket;

  //==============================================================================
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(TutorialProcessor)
};
