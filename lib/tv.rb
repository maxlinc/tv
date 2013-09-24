require 'tv/version'

require 'yaml'
require 'faraday'

begin
  require 'pacto'
  require 'vcr'
  VCR.configure do |c|
    c.default_cassette_options = {:record => :once}
    c.hook_into :webmock
    c.cassette_library_dir = 'cassettes'
  end
rescue LoadError
  # Will fallback to simple matching
end

module TV

  class << self

    include RSpec::Matchers

    def play(file)
      if defined?(VCR)
        VCR.insert_cassette file
      end

      raise "Could not find #{file}" unless File.exists?(file)
      interactions = YAML.load(File.read(file))['http_interactions']

      interactions.each do |interaction|
        request = interaction['request']
        response = interaction['response']

        connection = Faraday.new do |f|
          f.request  :url_encoded             # form-encode POST params
          f.response :logger                  # log requests to STDOUT
          f.adapter  Faraday.default_adapter  # make requests with Net::HTTP
        end

        actual = connection.send(request['method'].to_sym) do |method|
          method.url       request['uri']
          method.body =    request['body']
          method.headers = request['headers']
        end

      if defined?(Pacto)
        pacto_match(response, actual)
      else
        match(response, actual)
      end
      end
    end

    private

    def pacto_match(response, actual)
      contract_path = 'cassettes/license_contract.json'
      contract = Pacto.build_from_file(contract_path, 'https://github.com')
      Pacto.register_contract(contract)
      Pacto.use(:default)
      puts "Pacto - validating actual response:"
      puts contract.validate(actual)
      puts "Pacto - validating previously recorded response:"
      obj_response = OpenStruct.new(response)
      puts contract.validate(obj_response)
    end

    def match(expected, actual)
      expected['headers'].each do |k, v|
        case k
        when 'Date'
        else
          this = [actual.headers[k]].flatten
          that = [v].flatten

          this.should(eq(that), "Header '#{k}' did not match.\n  Expected: #{that}\n       Got: #{this}")
        end
      end

      actual.body.should == expected['body']
    end

  end
end
