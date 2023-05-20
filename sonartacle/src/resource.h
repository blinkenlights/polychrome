#pragma once
#include <JuceHeader.h>

#include <map>
#include <optional>
#include <string>

#include "error.h"

class Cache : public juce::URL::DownloadTaskListener
{
  typedef std::unique_ptr<juce::MemoryAudioSource> DataType;

 private:
  struct InternalDataType
  {
    std::unique_ptr<juce::AudioBuffer<float>> buffer;
    juce::String etag;
  };

 public:
  explicit Cache(juce::String const& cachePath) : m_cachePath(juce::File(cachePath)) {}
  ~Cache() {}

  [[nodiscard]] Error configure();

  [[nodiscard]] std::tuple<std::optional<DataType>, Error> get(juce::String const& uri);
  [[nodiscard]] Error cacheFile(juce::URL const& url, bool checkVersion = false);

 private:
  [[nodiscard]] std::tuple<juce::String, Error> download(juce::URL url,
                                                         juce::File const& destination,
                                                         bool checkVersion);
  [[nodiscard]] Error storeBufferFor(juce::String const& key, juce::File const& file,
                                     juce::String const& etag = "");

  // download status
  void progress(juce::URL::DownloadTask*, int64 bytesDownloaded, int64 totalLength) override;
  void finished(juce::URL::DownloadTask* task, bool success) override;

 private:
  juce::AudioFormatManager m_fmtManager;
  juce::File m_cachePath;
  std::map<juce::String, InternalDataType> m_ressourceMap;
  static constexpr double m_fileLengthLimitSeconds = 20;
};
