require 'spec_helper'

describe Arachni::HTTP::Request do
    it_should_behave_like 'Arachni::HTTP::Message'

    before( :all ) do
        @opts = Arachni::Options.instance
        @http = Arachni::HTTP::Client
        @url  = "#{web_server_url_for( :client )}/"
    end

    before( :each ) do
        @opts.reset
        @opts.audit.links = true
        @opts.url  = @url
        @http.reset
    end

    let(:url){ @url }
    let(:url_with_query) { "#{url}/?id=1&stuff=blah" }
    let(:options) do
        {
            url:        url,
            method:     :get,
            parameters: { 'test' => 'blah' },
            body: {
                '1' => ' 2',
                ' 3' => '4'
            },
            headers_string: 'stuff',
            effective_body: '1=%202&%203=4',
            timeout:    10_000,
            headers:    { 'Content-Type' => 'test/html' },
            cookies:    { 'cname'=> 'cvalue' },
            username:   'user',
            password:   'pass'
        }
    end
    subject do
        r = described_class.new( options )
        r.on_complete {}
        r
    end

    it "supports #{Marshal} serialization" do
        subject = described_class.new( options )
        expect(subject).to eq(Marshal.load( Marshal.dump( subject ) ))
    end

    it "supports #{Arachni::RPC::Serializer}" do
        subject = described_class.new( options )
        expect(subject).to eq(Arachni::RPC::Serializer.deep_clone( subject ))
    end

    describe '#to_rpc_data' do
        let(:data) { subject.to_rpc_data }

        %w(url method parameters body headers_string effective_body timeout
            headers cookies username password).each do |attribute|
            it "includes '#{attribute}'" do
                expect(data[attribute]).to eq(subject.send( attribute ))
            end
        end
    end

    describe '.from_rpc_data' do
        let(:restored) { described_class.from_rpc_data data }
        let(:data) { Arachni::RPC::Serializer.rpc_data( subject ) }

        %w(url method parameters body headers_string effective_body timeout
            headers cookies username password).each do |attribute|
            it "restores '#{attribute}'" do
                expect(restored.send( attribute )).to eq(subject.send( attribute ))
            end
        end

        it "does not include 'scope" do
            expect(data).not_to include 'scope'
        end
    end

    describe '#initialize' do
        it 'sets the instance attributes by the options' do
            r = described_class.new( options )
            expect(r.url).to          eq(Arachni::Utilities.normalize_url( url ))
            expect(r.method).to       eq(options[:method])
            expect(r.parameters).to   eq(options[:parameters])
            expect(r.timeout).to      eq(options[:timeout])
            expect(r.headers).to      eq(options[:headers])
            expect(r.username).to     eq(options[:username])
            expect(r.password).to     eq(options[:password])
        end

        it 'uses the setter methods when configuring' do
            options = { url: url, method: 'gEt', parameters: { test: 'blah' } }
            r = described_class.new( options )
            expect(r.method).to eq(:get)
            expect(r.parameters).to eq({ 'test' => 'blah' })
        end

        describe :fingerprint do
            context true do
                it 'enables fingerprinting' do
                    r = described_class.new( options.merge( fingerprint: true ) )
                    expect(r.fingerprint?).to be_truthy
                end
            end

            context false do
                it 'disables fingerprinting' do
                    r = described_class.new( options.merge( fingerprint: false ) )
                    expect(r.fingerprint?).not_to be_truthy
                end
            end

            context 'nil' do
                it 'enables fingerprinting' do
                    r = described_class.new( options.merge( fingerprint: nil ) )
                    expect(r.fingerprint?).to be_truthy
                end
            end
        end

        context 'when url is not a String' do
            it 'raises ArgumentError' do
                raised = false
                begin
                    described_class.new
                rescue ArgumentError
                    raised = true
                end
                expect(raised).to be_truthy
            end
        end
    end

    describe '#to_s' do
        it 'returns the HTTP request as a string' do
            request = described_class.new( url: @url ).run.request
            expect(request.to_s).to eq("#{request.headers_string}#{request.effective_body}")
        end
    end

    describe '#asynchronous?' do
        context 'when the mode is :async' do
            it 'returns true' do
                expect(described_class.new( url: @url, mode: :async )).to be_asynchronous
            end
        end

        context 'when the mode is :sync' do
            it 'returns false' do
                expect(described_class.new( url: @url, mode: :sync )).not_to be_asynchronous
            end
        end
    end

    describe '#blocking?' do
        context 'when the mode is :async' do
            it 'returns false' do
                expect(described_class.new( url: @url, mode: :async )).not_to be_blocking
            end
        end

        context 'when the mode is :sync' do
            it 'returns true' do
                expect(described_class.new( url: @url, mode: :sync )).to be_blocking
            end
        end
    end

    describe '#run' do
        it 'performs the request' do
            request  = described_class.new( url: @url )
            response = request.run

            expect(response).to be_kind_of Arachni::HTTP::Response
            expect(response.request).to eq(request)
        end

        it 'calls #on_complete callbacks' do
            request  = described_class.new( url: @url )

            called = []
            request.on_complete do |r|
                called << r
            end

            response = request.run
            expect(response).to be_kind_of Arachni::HTTP::Response
            expect(response.request).to eq(request)

            expect(called).to eq([response])
            expect(called.first.request).to eq(request)
        end

        it "fills in #{Arachni::HTTP::Request}#headers_string" do
            host = "#{Arachni::URI(@url).host}:#{Arachni::URI(@url).port}"
            expect(described_class.new( url: @url ).run.request.headers_string).to eq(
                "GET / HTTP/1.1\r\nHost: #{host}\r\nAccept-Encoding: gzip, " +
                    "deflate\r\nUser-Agent: Arachni/v#{Arachni::VERSION}\r\nAccept: text/html," +
                    "application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n\r\n"
            )
        end

        it "fills in #{Arachni::HTTP::Request}#effective_body" do
            expect(described_class.new(
                url: @url,
                body: {
                    '1' => ' 2',
                    ' 3' => '4'
                },
                mode:   :sync,
                method: :post
            ).run.request.effective_body).to eq("1=%202&%203=4")
        end
    end

    describe '#parameters' do
        it 'defaults to an empty Hash' do
            expect(described_class.new( url: url ).parameters).to eq({})
        end
    end

    describe '#parameters=' do
        it 'recursively forces converts keys and values to strings' do
            with_symbols = {
                test:         'blah',
                another_hash: {
                    stuff: 'test'
                }
            }
            with_strings = {
                'test'         => 'blah',
                'another_hash' => {
                    'stuff' => 'test'
                }
            }

            request = described_class.new( url: url )
            request.parameters = with_symbols
            expect(request.parameters).to eq(with_strings)
        end
    end

    describe '#on_complete' do
        context 'when passed a block' do
            it 'adds it as a callback to be passed the response' do
                request = described_class.new( url: url )

                passed_response = nil
                request.on_complete { |res| passed_response = res }

                response = Arachni::HTTP::Response.new( url: url )
                request.handle_response( response )

                expect(passed_response).to eq(response)
            end

            it 'can add multiple callbacks' do
                request = described_class.new( url: url )

                passed_responses = []

                2.times do
                    request.on_complete { |res| passed_responses << res }
                end

                response = Arachni::HTTP::Response.new( url: url )
                request.handle_response( response )

                expect(passed_responses.size).to eq(2)
                expect(passed_responses.uniq.size).to eq(1)
                expect(passed_responses.uniq.first).to eq(response)
            end
        end
    end

    describe '#clear_callbacks' do
        it 'clears #on_complete callbacks' do
            request = described_class.new( url: url )

            passed_response = nil
            request.on_complete { |res| passed_response = res }

            response = Arachni::HTTP::Response.new( url: url )
            request.clear_callbacks
            request.handle_response( response )

            expect(passed_response).to be_nil
        end
    end


    describe '#handle_response' do
        it 'assigns self as the #request attribute of the response' do
            request = described_class.new( url: url )

            passed_response = nil
            request.on_complete { |res| passed_response = res }

            response = Arachni::HTTP::Response.new( url: url )
            request.handle_response( response )

            expect(passed_response.request).to eq(request)
        end

        it 'calls #on_complete callbacks' do
            response = Arachni::HTTP::Response.new( url: url, code: 200 )
            request = described_class.new( url: url )

            passed_response = nil
            request.on_complete { |res| passed_response = res }
            request.handle_response( response )

            expect(passed_response).to eq(response)
        end
    end

    describe '#parsed_url' do
        it 'returns the configured URL as a parsed object' do
            expect(described_class.new( url: url ).parsed_url).to eq(Arachni::URI( url ))
        end
    end

    describe '#method' do
        it 'defaults to :get' do
            expect(described_class.new( url: url ).method).to eq(:get)
        end
    end

    describe '#method=' do
        it 'normalizes the HTTP method to a downcase symbol' do
            request = described_class.new( url: url )
            request.method = 'pOsT'
            expect(request.method).to eq(:post)
        end
    end

    describe '#mode=' do
        it 'normalizes and sets the given mode' do
            request = described_class.new( url: url )
            request.mode = 'aSyNC'
            expect(request.mode).to eq(:async)
        end

        context 'when an invalid mode is given' do
            it 'raises ArgumentError' do
                request = described_class.new( url: url )
                expect { request.mode = 'stuff' }.to raise_error ArgumentError
            end
        end
    end

    describe '#effective_cookies' do
        it 'returns the given :cookies merged with the cookies in Headers' do
            request = described_class.new(
                url: url,
                headers: {
                    'Cookie' => 'my_cookie=my_value; cookie2=value2'
                },
                cookies: {
                    'cookie2' => 'updated_value',
                    'cookie3' => 'value3',
                }
            )

            expect(request.cookies).to eq({
                'cookie2' => 'updated_value',
                'cookie3' => 'value3'
            })
            expect(request.effective_cookies).to eq({
                'my_cookie' => 'my_value',
                'cookie2'   => 'updated_value',
                'cookie3'   => 'value3'
            })
        end
    end

    describe '#id' do
        it 'is incremented by the Arachni::HTTP::Client' do
            10.times do |i|
                expect(@http.get( @url ).id).to eq(i)
            end
        end
    end

    describe '#train' do
        it 'sets train? to return true' do
            req = described_class.new( url: url )
            expect(req.train?).to be_falsey
            req.train
            expect(req.train?).to be_truthy
        end
    end

    describe '#update_cookies' do
        it 'sets update_cookies? to return true' do
            req = described_class.new( url: url )
            expect(req.update_cookies?).to be_falsey
            req.update_cookies
            expect(req.update_cookies?).to be_truthy
        end
    end

    describe '#to_typhoeus' do
        let(:request) { described_class.new( url: url ) }
        subject { request.to_typhoeus }

        it "converts #{described_class} to #{Typhoeus::Request}" do
            expect(subject).to be_kind_of Typhoeus::Request
        end

        context 'when the request is blocking' do
            let(:request) { described_class.new( url: url, mode: :sync ) }

            it 'forbids socket reuse' do
                expect(subject.options[:forbid_reuse]).to be_truthy
            end
        end

        context 'when the request is non-blocking' do
            let(:request) { described_class.new( url: url, mode: :async ) }

            it 'reuses sockets' do
                expect(subject.options[:forbid_reuse]).to be_falsey
            end
        end

        context 'when cookies are available' do
            let(:request) do
                described_class.new(
                    url:     url,
                    cookies: {
                        'na me'  => 'stu ff',
                        'na me2' => 'stu ff2'
                    }
                )
            end

            it 'encodes and puts them in the Cookie header' do
                expect(subject.options[:headers]['Cookie']).to eq('na+me=stu+ff;na+me2=stu+ff2')
            end
        end

        context 'when configured with a #proxy' do
            let(:request) do
                described_class.new(
                    url:   url,
                    proxy: 'http://stuff/'
                )
            end

            it 'forwards it' do
                expect(subject.options[:proxy]).to eq('http://stuff/')
            end

            context 'and #proxy_user_password' do
                let(:request) do
                    described_class.new(
                        url:   url,
                        proxy: 'http://stuff/',
                        proxy_user_password: 'name:secret'
                    )
                end

                it 'forwards it' do
                    expect(subject.options[:proxyuserpwd]).to eq('name:secret')
                end
            end

            context 'and #proxy_type' do
                let(:request) do
                    described_class.new(
                        url:   url,
                        proxy: 'http://stuff/',
                        proxy_type: :http
                    )
                end

                it 'forwards it' do
                    expect(subject.options[:proxytype]).to eq(:http)
                end
            end
        end

        context "when configured with a #{Arachni::OptionGroups::HTTP}#proxy_host/#{Arachni::OptionGroups::HTTP}#proxy_port" do
            before :each do
                Arachni::Options.http.proxy_host = 'stuff'
                Arachni::Options.http.proxy_port = '8080'
            end

            let(:request) do
                described_class.new( url: url )
            end

            it 'forwards it' do
                expect(subject.options[:proxy]).to eq('stuff:8080')
            end

            context "and #{Arachni::OptionGroups::HTTP}#proxy_username/#{Arachni::OptionGroups::HTTP}#proxy_password" do
                it 'forwards it' do
                    Arachni::Options.http.proxy_username = 'name'
                    Arachni::Options.http.proxy_password = 'secret'

                    expect(subject.options[:proxyuserpwd]).to eq('name:secret')
                end
            end

            context "and #{Arachni::OptionGroups::HTTP}#proxy_type" do
                it 'forwards it' do
                    Arachni::Options.http.proxy_type = 'http'
                    expect(subject.options[:proxytype]).to eq(:http)
                end
            end
        end

        context 'when configured with a #username and #password' do
            let(:request) do
                described_class.new(
                    url:   url,
                    username: 'name',
                    password: 'secret'
                )
            end

            it 'forwards it' do
                expect(subject.options[:userpwd]).to eq('name:secret')
            end

            it 'sets authentication type to :auto' do
                expect(subject.options[:httpauth]).to eq(:auto)
            end
        end

        context "and #{Arachni::OptionGroups::HTTP}#authentication_username/#{Arachni::OptionGroups::HTTP}#authentication_password" do
            before :each do
                Arachni::Options.http.authentication_username = 'name'
                Arachni::Options.http.authentication_password = 'secret'
            end

            let(:request) do
                described_class.new( url: url )
            end

            it 'forwards it' do
                expect(subject.options[:userpwd]).to eq('name:secret')
            end

            it 'sets authentication type to :auto' do
                expect(subject.options[:httpauth]).to eq(:auto)
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#response_max_size" do
            before :each do
                Arachni::Options.http.response_max_size = 10
            end

            context 'when #response_max_size' do
                context 'has not been set' do
                    it 'sets it as maxfilesize' do
                        expect(subject.options[:maxfilesize]).to eq(10)
                    end
                end

                context 'has been set' do
                    let(:request) do
                        described_class.new(
                            url:               url,
                            response_max_size: 1
                        )
                    end

                    it 'overrides it' do
                        expect(subject.options[:maxfilesize]).to eq(1)
                    end

                    context 'ands is < 0' do
                        let(:request) do
                            described_class.new(
                                url:               url,
                                response_max_size: -1
                            )
                        end

                        it 'removes it' do
                            expect(subject.options[:maxfilesize]).to be_nil
                        end
                    end
                end
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_verify_peer" do
            context 'true' do
                it "sets #{Typhoeus::Request}#options[:ssl_verifypeer]" do
                    Arachni::Options.http.ssl_verify_peer = true
                    expect(subject.options[:ssl_verifypeer]).to eq(true)
                end
            end

            context 'false' do
                it "sets #{Typhoeus::Request}#options[:ssl_verifypeer]" do
                    Arachni::Options.http.ssl_verify_peer = false
                    expect(subject.options[:ssl_verifypeer]).to eq(false)
                end
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_verify_host" do
            context 'true' do
                it "sets #{Typhoeus::Request}#options[:ssl_verifyhost] to 2" do
                    allow(Arachni::Options.http).to receive(:ssl_verify_host){ true }
                    expect(subject.options[:ssl_verifyhost]).to eq(2)
                end
            end

            context 'false' do
                it "sets #{Typhoeus::Request}#options[:ssl_verifyhost] to 2" do
                    allow(Arachni::Options.http).to receive(:ssl_verify_host){ false }
                    expect(subject.options[:ssl_verifyhost]).to eq(0)
                end
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_certificate_filepath" do
            it "sets #{Typhoeus::Request}#options[:sslcert]" do
                allow(Arachni::Options.http).to receive(:ssl_certificate_filepath){ :stuff }
                expect(subject.options[:sslcert]).to eq(:stuff)
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_certificate_type" do
            it "sets #{Typhoeus::Request}#options[:sslcerttype]" do
                allow(Arachni::Options.http).to receive(:ssl_certificate_type){ :stuff }
                expect(subject.options[:sslcerttype]).to eq(:stuff)
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_key_filepath" do
            it "sets #{Typhoeus::Request}#options[:sslkey]" do
                allow(Arachni::Options.http).to receive(:ssl_key_filepath){ :stuff }
                expect(subject.options[:sslkey]).to eq(:stuff)
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_key_type" do
            it "sets #{Typhoeus::Request}#options[:sslkeytype]" do
                allow(Arachni::Options.http).to receive(:ssl_key_type){ :stuff }
                expect(subject.options[:sslkeytype]).to eq(:stuff)
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_key_password" do
            it "sets #{Typhoeus::Request}#options[:sslkeypasswd]" do
                allow(Arachni::Options.http).to receive(:ssl_key_password){ :stuff }
                expect(subject.options[:sslkeypasswd]).to eq(:stuff)
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_ca_filepath" do
            it "sets #{Typhoeus::Request}#options[:cainfo]" do
                allow(Arachni::Options.http).to receive(:ssl_ca_filepath){ :stuff }
                expect(subject.options[:cainfo]).to eq(:stuff)
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_ca_directory" do
            it "sets #{Typhoeus::Request}#options[:capath]" do
                allow(Arachni::Options.http).to receive(:ssl_ca_directory){ :stuff }
                expect(subject.options[:capath]).to eq(:stuff)
            end
        end

        context "#{Arachni::OptionGroups::HTTP}#ssl_version" do
            it "sets #{Typhoeus::Request}#options[:sslversion]" do
                allow(Arachni::Options.http).to receive(:ssl_version){ :stuff }
                expect(subject.options[:sslversion]).to eq(:stuff)
            end
        end
    end

    describe '#to_h' do
        it 'returns a hash representation of self' do
            expect(described_class.new( options ).to_h).to eq(options.tap do |h|
                h.delete :timeout
                h.delete :cookies
                h.delete :username
                h.delete :password
            end)
        end
    end

    describe '#body_parameters' do
        context 'when #method is' do
            context :post do
                context 'and there are #parameters' do
                    it 'returns #parameters' do
                        parameters = { 'stuff' => 'here' }
                        expect(described_class.new(
                            url:        url,
                            parameters: parameters,
                            method:     :post
                        ).body_parameters).to eq(parameters)
                    end
                end

                context 'and there are no #parameters' do
                    it 'parses the #body' do
                        body = 'stuff=here&and_here=too'
                        expect(described_class.new(
                            url:    url,
                            body:   body,
                            method: :post
                        ).body_parameters).to eq({
                            'stuff'    => 'here',
                            'and_here' => 'too'
                        })
                    end

                    context 'and content-type is multipart/form-data' do
                        let(:body) do
                            "--myboundary\r\nContent-Disposition: form-data; name=\"name1\"\r\n\r\nval1\r\n--myboundary\r\nContent-Disposition: form-data; name=\"name2\"\r\n\r\nval2\r\n--myboundary--\r\n"
                        end

                        it 'parses the #body' do
                            expect(described_class.new(
                                url:    url,
                                body:   body,
                                method: :post,
                                headers: {
                                    'Content-Type' => 'multipart/form-data; boundary=myboundary'
                                }
                            ).body_parameters).to eq({
                                'name1'    => 'val1',
                                'name2'    => 'val2'
                            })
                        end

                        context 'but is missing a boundary' do
                            it 'returns empty hash' do
                                expect(described_class.new(
                                    url:    url,
                                    body:   body,
                                    method: :post,
                                    headers: {
                                        'Content-Type' => 'multipart/form-data'
                                    }
                                ).body_parameters).to be_empty
                            end
                        end

                        context 'and the body is incomplete' do
                            let(:body) do
                                "--myboundary\r\nContent-Disposition: form-data; name=\"name1\"\r\n\r\nval1\r\n--myboundary\r\nContent-Disposition: form-data; name=\"name2\"\r\n\r\nval2\r\n"
                            end

                            it 'returns partial data' do
                                expect(described_class.new(
                                    url:    url,
                                    body:   body,
                                    method: :post,
                                    headers: {
                                        'Content-Type' => 'multipart/form-data; boundary=myboundary'
                                    }
                                ).body_parameters).to eq({
                                    'name1' => 'val1'
                                })
                            end
                        end
                    end
                end
            end

            context 'other' do
                it 'returns an empty Hash' do
                    expect(described_class.new( url: url ).body_parameters).to eq({})
                end
            end
        end
    end

    describe '.parse_body' do
        it 'parses the request body into a Hash' do
            expect(described_class.parse_body( 'value%5C+%2B%3D%26%3B=value%5C+%2B%3D%26%3B&testID=53738&deliveryID=53618&testIDs=&deliveryIDs=&selectedRows=2&event=&section=&event%3Dmanage%26amp%3Bsection%3Dexam=Manage+selected+exam' )).to eq(
                {
                    "value\\ +=&;" => "value\\ +=&;",
                    "testID" => "53738",
                    "deliveryID" => "53618",
                    "testIDs" => "",
                    "deliveryIDs" => "",
                    "selectedRows" => "2",
                    "event" => "",
                    "section" => "",
                    "event=manage&amp;section=exam" => "Manage selected exam"
                }
            )
        end

        context 'when the body is nil' do
            it 'returns an empty Hash' do
                expect(described_class.parse_body(nil)).to eq({})
            end
        end
    end
end
