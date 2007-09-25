module Sinatra
  
  module EventManager
    extend self

    def reset!
      @events.clear if @events
    end

    def events
      @events || []
    end
    
    def register_event(event)
      (@events ||= []) << event
    end
    
    def determine_event(verb, path, if_nil = :present_error)
      event = events.find(method(if_nil)) do |e|
        e.verb == verb && e.recognize(path)
      end
    end
    
    def present_error
      determine_event(:get, '404', :not_found)
    end
    
    def not_found
      Event.new(:get, 'not_found', false) do
        status 404
        views_dir SINATRA_ROOT + '/files'
    
        if request.path_info == '/' && request.request_method == 'GET'
          erb :default_index
        else
          erb :not_found
        end
      end
    end
    
  end
  
  class EventContext

    cattr_accessor :logger
    
    attr_reader :request
    
    def initialize(request)
      @request = request
      @headers = {}
    end
    
    def status(value = nil)
      @status = value if value
      @status || 200
    end
    
    def body(value = nil, &block)
      @body = value if value
      @body = block.call if block
      @body
    end
    
    def error(value = nil)
      if value
        @error = value
        status 500
      end
      @error
    end
        
    # This allows for:
    #  header 'Content-Type' => 'text/html'
    #  header 'Foo' => 'Bar'
    # or
    #  headers 'Content-Type' => 'text/html',
    #          'Foo' => 'Bar'
    # 
    # Whatever blows your hair back
    def headers(value = nil)
      @headers.merge!(value) if value
      @headers
    end
    alias :header :headers
    
    def session
      request.env['rack.session']
    end

    def params
      @params ||= @request.params.symbolize_keys
    end
    
    def views_dir(value = nil)
      @views_dir = value if value
      @views_dir || File.dirname($0) + '/views'
    end
    
    def determine_template(content, ext)
      if content.is_a?(Symbol)
        File.read("%s/%s.%s" % [views_dir, content, ext])
      else
        content
      end
    end
    
    def log_event
      logger.info "#{request.request_method} #{request.path_info} | Status: #{status} | Params: #{params.inspect}"
      logger.exception(error) if error
    end
    
  end
  
  class Event

    cattr_accessor :logger
    cattr_accessor :after_filters
    
    self.after_filters = []
    
    def self.after_attend(filter)
      after_filters << filter
    end
    
    after_attend :log_event
    
    attr_reader :path, :verb
    
    def initialize(verb, path, register = true, &block)
      @verb = verb
      @path = path
      @route = Route.new(path)
      @block = block
      EventManager.register_event(self) if register
    end
    
    def attend(request)
      request.params.merge!(@route.params)
      context = EventContext.new(request)
      begin
        result = context.instance_eval(&@block) if @block
        context.body context.body || result || ''
      rescue => e
        context.error e
      end
      run_through_after_filters(context)
      context
    end
    alias :call :attend

    def recognize(path)
      @route.recognize(path)
    end

    private
    
      def run_through_after_filters(context)
        after_filters.each { |filter| context.send(filter) }
      end
      
  end
  
  class StaticEvent < Event
    
    def initialize(path, root, register = true)
      @root = root
      super(:get, path, register)
    end

    def recognize(path)
      File.exists?(physical_path_for(path))
    end
    
    def physical_path_for(path)
      path.gsub(/^#{@path}/, @root)
    end
    
    def attend(request)
      @filename = physical_path_for(request.path_info)
      context = EventContext.new(request)
      context.body self
      context.header 'Content-Type' => MIME_TYPES[File.extname(@filename)[1..-1]]
      context.header 'Content-Length' => File.size(@filename).to_s
      context
    end
    
    def each
      File.open(@filename, "rb") do |file|
        while part = file.read(8192)
          yield part
        end
      end
    end
    
    # :stopdoc:
    # From WEBrick.
    MIME_TYPES = {
      "ai"    => "application/postscript",
      "asc"   => "text/plain",
      "avi"   => "video/x-msvideo",
      "bin"   => "application/octet-stream",
      "bmp"   => "image/bmp",
      "class" => "application/octet-stream",
      "cer"   => "application/pkix-cert",
      "crl"   => "application/pkix-crl",
      "crt"   => "application/x-x509-ca-cert",
     #"crl"   => "application/x-pkcs7-crl",
      "css"   => "text/css",
      "dms"   => "application/octet-stream",
      "doc"   => "application/msword",
      "dvi"   => "application/x-dvi",
      "eps"   => "application/postscript",
      "etx"   => "text/x-setext",
      "exe"   => "application/octet-stream",
      "gif"   => "image/gif",
      "htm"   => "text/html",
      "html"  => "text/html",
      "jpe"   => "image/jpeg",
      "jpeg"  => "image/jpeg",
      "jpg"   => "image/jpeg",
      "lha"   => "application/octet-stream",
      "lzh"   => "application/octet-stream",
      "mov"   => "video/quicktime",
      "mpe"   => "video/mpeg",
      "mpeg"  => "video/mpeg",
      "mpg"   => "video/mpeg",
      "pbm"   => "image/x-portable-bitmap",
      "pdf"   => "application/pdf",
      "pgm"   => "image/x-portable-graymap",
      "png"   => "image/png",
      "pnm"   => "image/x-portable-anymap",
      "ppm"   => "image/x-portable-pixmap",
      "ppt"   => "application/vnd.ms-powerpoint",
      "ps"    => "application/postscript",
      "qt"    => "video/quicktime",
      "ras"   => "image/x-cmu-raster",
      "rb"    => "text/plain",
      "rd"    => "text/plain",
      "rtf"   => "application/rtf",
      "sgm"   => "text/sgml",
      "sgml"  => "text/sgml",
      "tif"   => "image/tiff",
      "tiff"  => "image/tiff",
      "txt"   => "text/plain",
      "xbm"   => "image/x-xbitmap",
      "xls"   => "application/vnd.ms-excel",
      "xml"   => "text/xml",
      "xpm"   => "image/x-xpixmap",
      "xwd"   => "image/x-xwindowdump",
      "zip"   => "application/zip",
    }
    # :startdoc:
  
  end  
  
end
