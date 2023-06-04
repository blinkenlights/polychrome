#pragma once
#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_core/juce_core.h>

#include <map>
#include <optional>
#include <string>

#include "error.h"

namespace beak
{
class Cache : public juce::URL::DownloadTaskListener
{
  typedef juce::File DataType;

 private:
  struct InternalDataType
  {
    DataType buffer;
    juce::String etag;
  };

 public:
  explicit Cache(juce::String const& cachePath) : m_cachePath(juce::File(cachePath)) {}

  [[nodiscard]] Error configure();

  [[nodiscard]] std::tuple<std::optional<DataType>, Error> get(juce::String const& uri);
  [[nodiscard]] Error cacheFile(juce::URL const& url, bool checkVersion = false);

 private:
  [[nodiscard]] std::tuple<juce::String, Error> download(juce::URL url,
                                                         juce::File const& destination,
                                                         bool checkVersion);
  [[nodiscard]] Error storeItem(juce::String const& key, juce::File const& file,
                                juce::String const& etag = "");

  // download status
  void progress(juce::URL::DownloadTask*, juce::int64 bytesDownloaded,
                juce::int64 totalLength) override;
  void finished(juce::URL::DownloadTask* task, bool success) override;

 private:
  juce::AudioFormatManager m_fmtManager;
  juce::File m_cachePath;
  std::map<juce::String, InternalDataType> m_ressourceMap;
  static constexpr double m_fileLengthLimitSeconds = 20;
};
}  // namespace beak
