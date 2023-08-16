#include "app.h"

#include <plog/Log.h>

#include <chrono>

#include "engine.h"
#include "filter.h"
#include "plog/Formatters/TxtFormatter.h"
#include "plog/Initializers/ConsoleInitializer.h"
#include "resource.h"
#include "server.h"
#include "simEngine.h"

namespace beak
{
constexpr auto stopThreadTimeoutMs =
    std::chrono::milliseconds(100);  //!< Interval after which to terminate the thread
/**
 * @brief Construct a new Main App:: Main App object
 *
 */
MainApp::MainApp() : Thread("beak")
{
  // declare commands to be used
  addHelpCommand("--help|-h", "Usage:", true);
  addVersionCommand("--version|-v", "Multi channel sampler 0.0.1");
  addCommand({
      "list-devices",
      "list-devices",
      "Lists available devices",
      "This command lists all available devices on your computer",
      [this](juce::ArgumentList const &args) { listCmd(args); },
  });
  addCommand({
      "play",
      "play",
      "Plays an audio file on a specified channel",
      "",
      [this](juce::ArgumentList const &args) { playCmd(args); },
  });
  addDefaultCommand({
      "server",
      "server",
      "Starts the udp server",
      "This command runs a udp server with an protobuf api.",
      [this](juce::ArgumentList const &args) { serverCmd(args); },
  });
}

/**
 * @brief Destroy the Main App:: Main App object
 *
 */
MainApp::~MainApp()
{
  juce::MessageManager::deleteInstance();
  juce::DeletedAtShutdown::deleteAll();
}

/**
 * @brief Reimplemented to initialise JUCEApplication
 *
 * @param args
 */
void MainApp::initialise(const juce::String &args)
{
  static plog::ColorConsoleAppender<plog::TxtFormatter> consoleAppender;
  plog::init(plog::debug, &consoleAppender);
  PLOGI << "Starting " << getApplicationName() << "v" << getApplicationVersion();
  m_args = args;
  startThread(juce::Thread::Priority::highest);
}

/**
 * @brief Reimplemented to shutdown the JUCEApplication
 *
 */
void MainApp::shutdown()
{
  PLOGI << "shutting down...";
  signalThreadShouldExit();
}

/**
 * @brief Reimplemented to run the thread for the main app
 *
 * Run the command in a seperate thread, because the event loop will be run in the main thread.
 *
 */
void MainApp::run() { findAndRunCommand(juce::ArgumentList("beak", m_args), false); }

/* -------------------------------- commands -------------------------------- */

/**
 * @brief Command to list the available devices
 *
 */
void MainApp::listCmd(juce::ArgumentList const & /*args*/)
{
  juce::OwnedArray<juce::AudioIODeviceType> devTypes;
  juce::AudioDeviceManager deviceManager;
  deviceManager.createAudioDeviceTypes(devTypes);
  for (const auto &type : devTypes)
  {
    std::cout << "[[ " << type->getTypeName() << " ]]" << std::endl;
    type->scanForDevices();
    for (const auto &dev : type->getDeviceNames())
    {
      std::cout << "  - " << dev << std::endl;
    }
  }
  juce::JUCEApplication::getInstance()->systemRequestedQuit();
}

/**
 * @brief Command to play one sample
 *
 * @param args Command line arguments
 */
void MainApp::playCmd(juce::ArgumentList const &args)
{
  const juce::String device = args.getValueForOption("--device|-d");
  const int outputs = args.getValueForOption("--outputs|-o").getIntValue();
  const juce::File file = args.getExistingFileForOption("--file|-f");
  const int channel = args.getValueForOption("--channel|-c").getIntValue();

  Engine engine;
  if (auto err = engine.configure(Engine::Config().WithDeviceName(device).WithOutputs(outputs));
      err)
  {
    PLOGF << err.what();
    std::terminate();
  }

  if (auto err = engine.playSound(file, channel); err)
  {
    PLOGF << err.what();
    std::terminate();
  }
}

/**
 * @brief Command to run the udp server
 *
 * @param args Command line arguments
 */
void MainApp::serverCmd(juce::ArgumentList const &args)
{
  // parse arguments
  uint32_t port = args.getValueForOption("--port|-p").getIntValue();
  const int outputs = args.getValueForOption("--outputs|-o").getIntValue();
  const int inputs = args.getValueForOption("--inputs|-i").getIntValue();
  const juce::String device = args.getValueForOption("--device|-d");
  juce::String cacheDir = args.getValueForOption("--cache|-c");
  const bool isSimulation = args.containsOption("--sim|-s");
  juce::String resourceDir = args.getValueForOption("--resource-dir|-r");

  port = port != 0 ? port : defaultPort;                   // default port
  cacheDir = cacheDir.isEmpty() ? "/tmp/beak" : cacheDir;  // default cache dir
  resourceDir = resourceDir.isEmpty() ? "./resources" : resourceDir;

  // setup chaching
  Cache cache(cacheDir, resourceDir);
  if (auto err = cache.configure())
  {
    PLOGF << err.what();
    std::terminate();
  }

  // setup aduio engine
  std::unique_ptr<Engine> engine;
  if (isSimulation)
  {
    engine = std::make_unique<sim::SimulationEngine>(outputs);
    if (auto err = engine->configure(Engine::Config()
                                         .WithDeviceName(device)
                                         .WithInputs(inputs)
                                         .WithOutputs(2)
                                         .WithSampleRate(Engine::Config::defaultSampleRate)))
    {
      PLOGF << err.what();
      std::terminate();
    }
  }
  else
  {
    engine = std::make_unique<Engine>();
    if (auto err = engine->configure(Engine::Config()
                                         .WithDeviceName(device)
                                         .WithInputs(inputs)
                                         .WithOutputs(outputs)
                                         .WithSampleRate(Engine::Config::defaultSampleRate)))
    {
      PLOGF << err.what();
      std::terminate();
    }
  }
  try
  {
    asio::io_context ioCtx;
    net::Server server(ioCtx, port);

    // register callback to play a sample
    server.registerCallback(Packet::kAudioFrame,
                            [&engine, &cache](std::shared_ptr<Packet> packet)
                            {
                              auto uri = packet->audio_frame().uri();
                              auto channel = static_cast<int>(packet->audio_frame().channel());
                              if (auto [file, err] = cache.get(uri); !err)
                              {
                                if (auto err = engine->playSound(file.value(), channel))
                                {
                                  PLOGE << err.what();
                                }
                              }
                              else
                              {
                                PLOGE << err.what();
                              }
                            });

    server.registerCallback(
        Packet::kSynthFrame,
        [&engine](std::shared_ptr<Packet> packet)
        {
          static auto translateProtoWaveform =
              [](const SynthWaveform &in) -> synth::Oscillator::Type
          {
            static const std::unordered_map<SynthWaveform, synth::Oscillator::Type>
                translationTable{
                    {SynthWaveform::SINE, synth::Oscillator::Type::Sine},
                    {SynthWaveform::SAW, synth::Oscillator::Type::Saw},
                    {SynthWaveform::SQUARE, synth::Oscillator::Type::Square},

                };
            return translationTable.at(in);
          };

          static auto translateProtoFilterType =
              [](const SynthFilterType &in) -> synth::Filter::Type
          {
            static const std::unordered_map<SynthFilterType, synth::Filter::Type> translationTable{
                {SynthFilterType::LOWPASS, synth::Filter::Type::Lowpass},
                {SynthFilterType::HIGHPASS, synth::Filter::Type::Highpass},
                {SynthFilterType::BANDPASS, synth::Filter::Type::Bandpass},
            };
            return translationTable.at(in);
          };

          const auto synthFrame = packet->synth_frame();
          // we only want to set the config if it is a config frame or a
          if (synthFrame.event_type() == CONFIG || synthFrame.event_type() == NOTE_ON)
          {
            const auto config = synthFrame.config();

            // oscillator config
            synth::Oscillator::Parameters oscParams(translateProtoWaveform(config.wave_form()),
                                                    config.gain());

            // adsr config
            const auto adsrConfig = config.adsr_config();
            juce::ADSR::Parameters adsrParams(adsrConfig.attack(), adsrConfig.decay(),
                                              adsrConfig.sustain(), adsrConfig.release());
            // filter config
            synth::Filter::Parameters filterParams(translateProtoFilterType(config.filter_type()),
                                                   config.cutoff(), config.resonance());
            const auto filterAdsrConfig = config.filter_adsr_config();
            juce::ADSR::Parameters filterAdsrParams(
                filterAdsrConfig.attack(), filterAdsrConfig.decay(), filterAdsrConfig.sustain(),
                filterAdsrConfig.release());

            // configure the channel
            if (Error err = engine->configureSynth(synthFrame.channel(), oscParams, adsrParams,
                                                   filterParams, filterAdsrParams))
            {
              PLOGE << err.what();
            }
          }
          // we only need the config here
          if (synthFrame.event_type() == CONFIG)
          {
            return;
          }
          juce::MidiMessage msg{};
          switch (synthFrame.event_type())
          {
            case SynthEventType::NOTE_ON:
              msg = juce::MidiMessage::noteOn(synthFrame.channel(), synthFrame.note(),
                                              synthFrame.velocity());
              // PLOGD << "note on, channel " << synthFrame.channel() << ", note "
              //       << synthFrame.note();
              break;
            case SynthEventType::NOTE_OFF:
              msg = juce::MidiMessage::noteOff(synthFrame.channel(), synthFrame.note());
              // PLOGD << "note off, channel " << synthFrame.channel() << ", note "
              //       << synthFrame.note();
              break;
            default:
              PLOGE << "unkown event type";
          }
          if (Error err = engine->playSynth(msg, synthFrame.duration_ms()))
          {
            PLOGE << err.what();
          }
        });

    // run the server
    while (true)
    {
      ioCtx.run_one_for(stopThreadTimeoutMs);
      if (threadShouldExit())
      {
        PLOGI << "stopping server...";
        return;
      }
    }
  }
  catch (std::exception &e)
  {
    PLOGF << e.what();
    std::terminate();
  }
}
}  // namespace beak

/**
 *
 * Start the JUCEApplication, int main() is here.
 */
START_JUCE_APPLICATION(beak::MainApp)
