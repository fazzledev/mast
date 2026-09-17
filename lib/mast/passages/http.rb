require "net/http"
require "uri"

module Mast
  module Passages
    module HTTP
      module_function

      def get(url, redirects = 5)
        uri = URI(url)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                              open_timeout: 30, read_timeout: 30) do |http|
          http.request(Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT))
        end
        return get(URI.join(url, res["location"]).to_s, redirects - 1) if res.is_a?(Net::HTTPRedirection) && redirects > 0
        raise "#{url}: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        res.body.force_encoding("UTF-8").scrub
      end
    end
  end
end
