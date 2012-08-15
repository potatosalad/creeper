require 'beanstalk-client'

module Creeper
  class BeanstalkConnection
    def self.create(options={})
      client_options.merge!(options)

      url     = client_options[:url] || ENV['BEANSTALK_URL'] || 'beanstalk://127.0.0.1:11300/'
      default = client_options[:default]
      tubes   = client_options[:tubes] || Creeper.job_descriptions.keys

      build_client(url, default, tubes)
    end

    def self.build_client(urls, default, tubes)
      uris = [*urls].flatten.map do |url_string|
        url_string.split(/[\s,]+/).map do |url|
          uri = URI.parse(url)
          "#{uri.host}:#{uri.port || 11300}"
        end
      end.flatten

      Beanstalk::Pool.new(uris, default).tap do |client|
        tubes.each do |tube|
          client.watch(tube)
        end
      end
    end
    private_class_method :build_client

    def self.client_options
      @client_options ||= {}
    end
  end
end
