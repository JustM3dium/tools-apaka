require 'date'
require 'json'
require 'open3'
require 'digest/sha2'
require 'thread'

module Apaka
    # This class will implement a thread safe cache. The main purpose of this cache will be to store the content
    # of json files.
    # The cache will be used in the GemDependencie class to cache the result of the gem dependencies.
    # This cache will safe it's content in the following form:
    #   { key => {"datetime" => current date,
    #              "result" => jsonfile}
    #   }
    # The key is the sha256 representation of the url.
    class Cache

        # Initialization of the cache class.
        # @param cache_path [String] (Default: /tmp/apaka/cache_content.json) Path where the cache content will be stored.
        # @param expiration_date [Integer] (Default: 1) Determines after how many days the cache entry is expired.
        def initialize(cache_path = "/tmp/apaka/cache_content.json", expiration_date=1)
            @cache_content = Hash.new
            @mutex = Mutex.new
            @locked = false
            @cache_path = cache_path
            @expiration_date = expiration_date

            unless File.exist?(File.dirname(@cache_path))
                Dir.mkdir(File.dirname(@cache_path))
            end
            read_cache_content
        end

        # Check if the mutex file is locked and if the cache_path is writable.
        def writable?
            @mutex.synchronize { !@locked }
        end

        # Make the cache content persistent by safeing it to disk.
        # @param path_to_file [String] (Default: (@cache_path) /tmp/apaka/cache_content.json) Path where the cache content is stored.
        def write_cache_content(path_to_file=@cache_path)
            unless writable?
                @mutex.synchronize do
                    File.write(path_to_file, JSON.dump(@cache_content))
                    @locked = false
                end
            end
        end

        # Read the cache content.
        def read_cache_content
            if File.exist? @cache_path
                cache_content = File.read(@cache_path)
                @cache_content = JSON.parse(cache_content)
            end
        end

        # Get current date.
        def get_current_date
            DateTime.now
        end

        # Get a web result from an url. This method assumes, that the result is a json file.
        # @param url [String] Url of the target
        # @return The parsed json result if the json file is valid, nil otherwise
        def get_web_result(url)
            json_result, _, status = Open3.capture3("curl " + url)
            if status.success?
                begin
                    JSON.parse(json_result)
                rescue JSON::ParserError
                    nil
                end
            end
        end

        # Parse the datetime to get the date.
        # @param datetime [DateTime] The datetime object which shall be used
        # @return Parsed date in the format of "YYYY-MM-DD"
        def datetime_to_date(datetime)
            if datetime.class == String
                datetime = Date.parse datetime
            end
            Date.parse datetime.year.to_s + "-" + datetime.month.to_s + '-' + datetime.day.to_s
        end

        # Getting the web result from a given url and stores it in the cache.
        # @param url [String] Url of the target.
        # @param hash_sym [String] Sha256 representation of the url.
        # @return The parsed result of the json file.
        def cache_miss(url, hash_sym)
            web_result = get_web_result(url)
            @cache_content[hash_sym] = Hash["datetime" => get_current_date, "result" => web_result]
            write_cache_content
            web_result
        end

        # Get the information from the cache.
        # @param hash_sym [String] Sha256 representation of an url
        # @return The result of the cache
        def cache_hit(hash_sym)
            content = @cache_content[hash_sym]
            current_date = datetime_to_date(get_current_date)
            content_date = datetime_to_date(content['datetime'])

            unless content_date - current_date <= @expiration_date
                content['result']
            end
            nil
        end

        # This Method is the main method of the cache class. It will first create a SHA256 representation of the
        # url, then checks if the sha representation is already in the cache. If this is the case, the stored content
        # will be returned if the content is not older then the expiration date (cache_hit). Otherwise the url will be
        # accessed to save the content inside of the cache (cache_miss).
        # @param url [String] The url which shall be used
        # @param force_miss [Boolean] Can be used to force a cache miss and access the information from the url
        # @return The result of the web request
        def get_info(url, force_miss=false)
            sha_hash = Digest::SHA2.new(256).hexdigest url
            if @cache_content.has_key? sha_hash || force_miss
                hit_result = cache_hit(sha_hash)
                unless hit_result.nil?
                    hit_result
                end
            end
            cache_miss(url, sha_hash)
        end

        # Save the current content of the cache to the disk and empty the cache.
        def reset_cache
            old_cash_content = @cache_content
            @cache_content = Hash.new
            File.write(@cache_path + "_old", JSON.dump(old_cash_content))
        end
    end # Cache
end # Apaka

