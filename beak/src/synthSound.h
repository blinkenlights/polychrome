#pragma once

#include <juce_audio_basics/juce_audio_basics.h>

namespace beak::synth
{
class Sound : public juce::SynthesiserSound
{
 public:
  bool appliesToNote(int /*midiNoteNumber*/) override { return true; }
  bool appliesToChannel(int /*midiChannel*/) override { return true; }
};
}  // namespace beak::synth
