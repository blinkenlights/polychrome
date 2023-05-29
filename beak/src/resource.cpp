#include "resource.h"

#include <filesystem>
#include <sstream>

Error Cache::configure()
{
  m_fmtManager.registerBasicFormats();
  if (!m_cachePath.isDirectory())
  {
    if (auto res = m_cachePath.createDirectory(); res.failed())
      return Error("could not create cache directory");
  }
  return Error();
}

std::tuple<std::optional<Cache::DataType>, Error> Cache::get(juce::String const& uri)
{
  juce::URL url(uri);

  // check if already cached in memory
  if (m_ressourceMap.contains(url.toString(false)))
  {
    return std::make_tuple(std::make_unique<juce::MemoryAudioSource>(
                               *(m_ressourceMap.at(url.toString(false)).buffer), true),
                           Error());
  }
  else
  {
    // cache the file
    if (Error err = cacheFile(url); err) return std::make_tuple(std::nullopt, err);

    // create source
    if (!m_ressourceMap.contains(url.toString(false)))
    {
      std::stringstream err;
      err << "unknown error while caching '" << url.toString(false) << "'";
      return std::make_tuple(std::nullopt, Error(err.str()));
    }
    return std::make_tuple(std::make_unique<juce::MemoryAudioSource>(
                               *(m_ressourceMap.at(url.toString(false)).buffer), true),
                           Error());
  }
}

namespace fs = std::filesystem;
Error Cache::cacheFile(juce::URL const& url, bool checkVersion)
{
  // check if file is supported
  auto extension = fs::path(url.getFileName().toStdString()).extension();
  if (!m_fmtManager.findFormatForFileExtension(juce::String(extension)))
  {
    std::stringstream err;
    err << "unsupported file format for '" << url.toString(false) << "'";
    return Error(err.str());
  }

  if (url.isLocalFile())
  {
    // cache local file
    if (Error err = storeBufferFor(url.toString(false), url.getLocalFile()); err) return err;
  }
  else if (url.isWellFormed())
  {
    // cache remote file
    juce::File destination = juce::File(m_cachePath.getFullPathName() +
                                        juce::File::getSeparatorChar() + url.getFileName());

    auto [etag, err] = download(url, destination, checkVersion);
    if (err) return err;
    if (Error err = storeBufferFor(url.toString(false), destination, etag); err) return err;
  }
  return Error();
}

std::tuple<juce::String, Error> Cache::download(juce::URL url, juce::File const& destination,
                                                bool checkVersion)
{
  juce::URL::DownloadTaskOptions downloadOptions;
  downloadOptions = downloadOptions.withListener(this);
  if (m_ressourceMap.contains(url.toString(false)) && checkVersion)
    downloadOptions = downloadOptions.withExtraHeaders("If-None-Match: " +
                                                       m_ressourceMap.at(url.toString(false)).etag);

  juce::String etag;  //!< todo implement etags
  std::unique_ptr<juce::URL::DownloadTask> task = url.downloadToFile(destination, downloadOptions);
  if (!task)
  {
    return std::make_tuple(etag, Error("unable to download " + url.toString(false)));
  }
  while (!task->isFinished())
  {
    // wait for download
  }
  if (task->hadError() || task->statusCode() != 200)
  {
    std::stringstream err;
    err << "download failed, status: " << task->statusCode();
    return std::make_tuple(etag, Error(err.str()));
  }
  return std::make_tuple(etag, Error());
}

Error Cache::storeBufferFor(juce::String const& key, juce::File const& file,
                            juce::String const& etag)
{
  std::unique_ptr<juce::AudioFormatReader> reader(m_fmtManager.createReaderFor(file));
  if (!reader)
  {
    std::stringstream err;
    err << "creating reader for '" << file.getFullPathName() << "'";
    return Error(err.str());
  }

  auto duration = (float)reader->lengthInSamples / reader->sampleRate;
  if (duration > m_fileLengthLimitSeconds)
  {
    std::stringstream err;
    err << "file '" << file.getFullPathName() << "' is longer than maximum size of  "
        << m_fileLengthLimitSeconds << "s ";
    return Error(err.str());
  }

  std::unique_ptr<AudioSampleBuffer> buf(new AudioSampleBuffer());
  buf->setSize((int)reader->numChannels, (int)reader->lengthInSamples);
  if (!reader->read(buf.get(), 0, static_cast<int>(reader->lengthInSamples), 0, true, true))
    return Error("could not read into buffer");
  m_ressourceMap[key] = {
      std::move(buf),
      etag,
  };

  return Error();
}

void Cache::progress(juce::URL::DownloadTask*, int64 bytesDownloaded, int64 totalLength)
{
  double progress = static_cast<double>(bytesDownloaded) / static_cast<double>(totalLength);
  int barWidth = 70;

  std::cout << "[";
  int pos = barWidth * progress;
  for (int i = 0; i < barWidth; ++i)
  {
    if (i < pos)
      std::cout << "=";
    else if (i == pos)
      std::cout << ">";
    else
      std::cout << " ";
  }
  std::cout << "] " << int(progress * 100.0) << " %\r";
  std::cout.flush();

  if (progress >= 1.0) std::cout << std::endl;
}

void Cache::finished(juce::URL::DownloadTask* task, bool success)
{
  std::cout << std::endl;
  if (!success)
  {
    std::cerr << "error downloading '";
    std::cerr << task->getTargetLocation().getFullPathName();
    std::cerr << "' status code: " << task->statusCode() << std::endl;
    return;
  }
  else
  {
    std::cout << "Downloaded '" << task->getTargetLocation().getFullPathName() << "'" << std::endl;
  }
}
