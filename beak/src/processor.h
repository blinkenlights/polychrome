#pragma once
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>

#include <cassert>

namespace beak
{
using NodeID = juce::AudioProcessorGraph::NodeID;

class ProcessorBase : public juce::AudioProcessor
{
 public:
  ProcessorBase(const BusesProperties &ioConfig) : AudioProcessor(ioConfig){};
  ~ProcessorBase() override {}
  ProcessorBase(ProcessorBase &&) = delete;
  ProcessorBase &operator=(ProcessorBase &&) = delete;

  juce::AudioProcessorEditor *createEditor() override { return nullptr; }
  bool hasEditor() const override { return false; }

  void setName(juce::String const &name) { m_name = name; }
  const juce::String getName() const override { return m_name; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  double getTailLengthSeconds() const override { return 0; }

  int getNumPrograms() override { return 0; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}

  void getStateInformation(juce::MemoryBlock &) override {}
  void setStateInformation(const void *, int) override {}

 protected:
  juce::String m_name;

 private:
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ProcessorBase)
};

class PanningProcessor : public ProcessorBase
{
 public:
  explicit PanningProcessor(int inputNum, int maxInputs);
  ~PanningProcessor() override;
  PanningProcessor(PanningProcessor &&) = delete;
  PanningProcessor &operator=(PanningProcessor &&) = delete;

  void prepareToPlay(double sampleRate, int samplesPerBlock) override;
  void processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &) override;
  void reset() override;
  void releaseResources() override;

 private:
  int m_inputNum;
  int m_maxInputs;
  juce::dsp::Panner<float> m_panner;

 private:
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PanningProcessor)
};

class SamplerProcessor : public ProcessorBase, public juce::ChangeListener
{
 public:
  explicit SamplerProcessor();
  ~SamplerProcessor() override;
  SamplerProcessor(SamplerProcessor &&) = delete;
  SamplerProcessor &operator=(SamplerProcessor &&) = delete;

  void prepareToPlay(double sampleRate, int maximumExpectedSamplesPerBlock) override;
  void processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &) override;
  void reset() override;
  void releaseResources() override;
  void playSample(juce::File const &file);

  void changeListenerCallback(juce::ChangeBroadcaster *source) override;

 private:
  juce::AudioFormatManager m_formatManager;
  juce::MixerAudioSource m_source;

 private:
  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SamplerProcessor)
};

// struct SineWaveSound : public juce::SynthesiserSound
// {
//   SineWaveSound() {}

//   bool appliesToNote(int) override { return true; }
//   bool appliesToChannel(int) override { return true; }
// };

// class SquareSynthVoice : public juce::SynthesiserVoice
// {
//  public:
//   SquareSynthVoice() {}

//   void setCurrentPlaybackSampleRate(double newSampleRate) override
//   {
//     juce::SynthesiserVoice::setCurrentPlaybackSampleRate(newSampleRate);
//     m_adsr.setSampleRate(newSampleRate);
//   }

//   bool canPlaySound(juce::SynthesiserSound *sound) override
//   {
//     return dynamic_cast<SineWaveSound *>(sound) != nullptr;
//   }

//   void setADSRParameters(const juce::ADSR::Parameters &params) { m_adsr.setParameters(params); }

//   void startNote(int midiNoteNumber, float velocity, juce::SynthesiserSound * /*sound*/,
//                  int /*currentPitchWheelPosition*/) override
//   {
//     m_currentAngle = 0.0;
//     m_level = velocity * 0.15;

//     auto cyclesPerSecond = juce::MidiMessage::getMidiNoteInHertz(midiNoteNumber);
//     auto cyclesPerSample = cyclesPerSecond / getSampleRate();
//     m_angleDelta = cyclesPerSample * 2.0 * juce::MathConstants<double>::pi;
//   }

//   void stopNote(float velocity, bool allowTailOff) override
//   {
//     if (!m_adsr.isActive())
//     {
//       clearCurrentNote();
//     }
//     else
//     {
//       m_adsr.noteOff();
//     }
//     // if (allowTailOff)
//     // {
//     //   if (m_tailOff == 0.0)
//     //     m_tailOff = 1.0;
//     // }
//     // else
//     // {
//     //   clearCurrentNote();
//     //   m_angleDelta = 0.0;
//     // }
//   }
//   void pitchWheelMoved(int newPitchWheelValue) override {}
//   void controllerMoved(int controllerNumber, int newControllerValue) override {}
//   void renderNextBlock(juce::AudioBuffer<float> &outputBuffer, int startSample,
//                        int numSamples) override
//   {
//     const int firstSample = startSample;
//     if (m_angleDelta != 0.0)
//     {
//       while (--numSamples >= 0)
//       {
//         auto currentSample = (float)(std::sin(m_currentAngle) * m_level);

//         for (auto i = outputBuffer.getNumChannels(); --i >= 0;)
//           outputBuffer.addSample(i, startSample, currentSample);

//         m_currentAngle += m_angleDelta;
//         ++startSample;
//       }
//       m_adsr.applyEnvelopeToBuffer(outputBuffer, firstSample, numSamples);
//     }
//   }

//  private:
//   double m_currentAngle;
//   double m_angleDelta;
//   // double m_tailOff;
//   double m_level;
//   juce::ADSR m_adsr;
// };

// class SynthSound : public juce::AudioSource
// {
//  public:
//   SynthSound(juce::MidiKeyboardState &keyState) : m_keyboardState(keyState)
//   {
//     m_synth.addVoice(new SquareSynthVoice());
//   }
//   void prepareToPlay(int /*samplesPerBlock*/, double sampleRate) override
//   {
//     m_synth.setCurrentPlaybackSampleRate(sampleRate);
//     m_midiCollector.reset(sampleRate);
//   }
//   void releaseResources() override {}

//   void getNextAudioBlock(const juce::AudioSourceChannelInfo &bufferToFill) override
//   {
//     bufferToFill.clearActiveBufferRegion();
//     juce::MidiBuffer incomingMidi;
//     m_midiCollector.removeNextBlockOfMessages(incomingMidi, bufferToFill.numSamples);  // [11]

//     m_keyboardState.processNextMidiBuffer(incomingMidi, bufferToFill.startSample,
//                                           bufferToFill.numSamples, true);

//     m_synth.renderNextBlock(*bufferToFill.buffer, incomingMidi, bufferToFill.startSample,
//                             bufferToFill.numSamples);
//     // m_adsr.applyEnvelopeToBuffer(*bufferToFill.buffer, bufferToFill.startSample,
//     //                              bufferToFill.numSamples);
//   }
//   juce::MidiMessageCollector *getMidiCollector() { return &m_midiCollector; }

//   // void setADSRParameters(const juce::ADSR::Parameters &params) { m_adsr.setParameters(params);
//   }

//  private:
//   juce::MidiKeyboardState &m_keyboardState;
//   juce::Synthesiser m_synth;
//   juce::MidiMessageCollector m_midiCollector;
// };

// class SynthProcessor : public ProcessorBase
// {
//  public:
//   SynthProcessor();
//   void prepareToPlay(double sampleRate, int maximumExpectedSamplesPerBlock) override
//   {
//     m_sound->prepareToPlay(maximumExpectedSamplesPerBlock, sampleRate);
//   }
//   void processBlock(juce::AudioSampleBuffer &buffer, juce::MidiBuffer &) override
//   {
//     auto info = juce::AudioSourceChannelInfo(buffer);
//     m_sound->getNextAudioBlock(info);
//   }
//   void reset() override {}
//   void releaseResources() override { m_sound->releaseResources(); }
//   void QueueMidiMsg(const juce::MidiMessage &msg, const juce::ADSR::Parameters &adsr = {})
//   {
//     m_sound->getMidiCollector()->addMessageToQueue(msg);
//   }

//  private:
//   SynthSound *m_sound;
// };

}  // namespace beak
