#include "resource.h"

#include <filesystem>
#include <sstream>

namespace beak
{
constexpr uint32_t statusOk = 200;  //!< HTTP ok status code.

/**
 * @brief Configure the cache
 *
 * @return Error  Custom error type to signal an error
 */
Error Cache::configure()
{
  m_fmtManager.registerBasicFormats();
  if (!m_cachePath.isDirectory())
  {
    if (auto res = m_cachePath.createDirectory(); res.failed())
    {
      return Error("could not create cache directory");
    }
  }
  return Error();
}

/**
 * @brief Get a resource from the cache from an uri
 *
 * @param uri   The uri to fetch the resource from
 * @return std::tuple<std::optional<Cache::DataType>, Error> Optionally the return data and an Error
 */
std::tuple<std::optional<Cache::DataType>, Error> Cache::get(juce::String const& uri)
{
  juce::URL const url(uri);

  // check if already cached
  if (m_ressourceMap.contains(url.toString(false)))
  {
    return std::make_tuple(m_ressourceMap.at(url.toString(false)).buffer, Error());
  }
  else
  {
    // cache the file
    if (Error const err = cacheFile(url); err)
    {
      return std::make_tuple(std::nullopt, err);
    }

    // create source
    if (!m_ressourceMap.contains(url.toString(false)))
    {
      std::stringstream err;
      err << "unknown error while caching '" << url.toString(false) << "'";
      return std::make_tuple(std::nullopt, Error(err.str()));
    }
    return std::make_tuple(m_ressourceMap.at(url.toString(false)).buffer, Error());
  }
}

namespace fs = std::filesystem;
/**
 * @brief Cache a file from a remote url
 *
 * @param url           The remote URL
 * @param checkVersion  Flag to signal if the version should be checked
 * @return Error        Custom error type to signal an error
 */
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
    if (auto err = storeItem(url.toString(false), url.getLocalFile()); err)
    {
      return err;
    }
  }
  else if (url.isWellFormed())
  {
    // cache remote file
    juce::File const destination = juce::File(m_cachePath.getFullPathName() +
                                              juce::File::getSeparatorChar() + url.getFileName());

    auto [etag, err] = download(url, destination, checkVersion);
    if (err)
    {
      return err;
    }
    if (auto err = storeItem(url.toString(false), destination, etag); err)
    {
      return err;
    }
  }
  return Error();
}

/**
 * @brief Downlioads a file to a destinantion path
 *
 * @param url           The url to download from
 * @param destination   The destinantion file path
 * @param checkVersion  Signal to check if there is a new version
 *
 * @return std::tuple<juce::String, Error> The etag and an error
 */
std::tuple<juce::String, Error> Cache::download(juce::URL url, juce::File const& destination,
                                                bool checkVersion)
{
  juce::URL::DownloadTaskOptions downloadOptions;
  downloadOptions = downloadOptions.withListener(this);
  if (m_ressourceMap.contains(url.toString(false)) && checkVersion)
  {
    downloadOptions = downloadOptions.withExtraHeaders("If-None-Match: " +
                                                       m_ressourceMap.at(url.toString(false)).etag);
  }

  juce::String const etag;  //!< todo implement etags
  std::unique_ptr<juce::URL::DownloadTask> task = url.downloadToFile(destination, downloadOptions);
  if (!task)
  {
    return std::make_tuple(etag, Error("unable to download " + url.toString(false)));
  }
  while (!task->isFinished())
  {
    juce::Thread::sleep(5);
    // wait for download
  }
  if (task->hadError() || task->statusCode() != statusOk)
  {
    std::stringstream err;
    err << "download failed, status: " << task->statusCode();
    return std::make_tuple(etag, Error(err.str()));
  }
  return std::make_tuple(etag, Error());
}

/**
 * @brief Stores one item in the cache
 *
 * @param key     Key to find the item
 * @param value   The acutal value to store
 * @param etag    The etag of this file version
 * @return Error  Error if something went wrong
 */
Error Cache::storeItem(juce::String const& key, DataType const& value, juce::String const& etag)
{
  // check if audio file is readable
  std::unique_ptr<juce::AudioFormatReader> reader(m_fmtManager.createReaderFor(value));
  if (!reader)
  {
    std::stringstream err;
    err << "creating reader for '" << value.getFullPathName() << "'";
    return Error(err.str());
  }

  // check for maximum duration
  auto duration = (float)reader->lengthInSamples / reader->sampleRate;
  if (duration > m_fileLengthLimitSeconds)
  {
    std::stringstream err;
    err << "file '" << value.getFullPathName() << "' is longer than maximum size of  "
        << m_fileLengthLimitSeconds << "s ";
    return Error(err.str());
  }

  m_ressourceMap[key] = {
      value,
      etag,
  };

  return Error();
}

/**
 * @brief Render the progress to stdout
 *
 * @param bytesDownloaded   Bytes already downloaded
 * @param totalLength       Length of the file in bytes
 */
void Cache::progress(juce::URL::DownloadTask*, juce::int64 bytesDownloaded, juce::int64 totalLength)
{
  double const progress = static_cast<double>(bytesDownloaded) / static_cast<double>(totalLength);
  int const barWidth = 70;

  std::cout << "[";
  int const pos = static_cast<int>(barWidth * progress);
  for (int i = 0; i < barWidth; ++i)
  {
    if (i < pos)
    {
      std::cout << "=";
    }
    else if (i == pos)
    {
      std::cout << ">";
    }
    else
    {
      std::cout << " ";
    }
  }
  std::cout << "] " << int(progress * 100.0) << " %\r";
  std::cout.flush();

  if (progress >= 1.0)
  {
    std::cout << std::endl;
  }
}

/**
 * @brief Reimplemented callback if a download has finished
 *
 * @param task      Pointer to the download task
 * @param success   boolean to signal if the download was successful
 */
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
}  // namespace beak
