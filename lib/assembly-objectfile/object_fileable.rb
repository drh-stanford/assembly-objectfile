require 'mini_exiftool'
require 'mime/types'
# require 'checksum-tools'

module Assembly
  # Common behaviors we need for other classes in the gem
  module ObjectFileable
    attr_accessor :path
    attr_accessor :file_attributes
    attr_accessor :label
    attr_accessor :provider_md5, :provider_sha1
    attr_accessor :relative_path

    # @param [String] path full path to the file to be worked with
    # @param [Hash<Symbol => Object>] params options used during content metadata generation
    # @option params [Hash<Symbol => ['yes', 'no']>] :file_attributes e.g. {:preserve=>'yes',:shelve=>'no',:publish=>'no'}, defaults pulled from mimetype
    # @option params [String] :label a resource label (files bundlded together will just get the first file's label attribute if set)
    # @option params [String] :provider_md5 pre-computed MD5 checksum
    # @option params [String] :provider_sha1 pre-computed SHA1 checksum
    # @option params [String] :relative_path if you want the file ids in the content metadata it can be set, otherwise content metadata will get the full path
    # @example
    #   Assembly::ObjectFile.new('/input/path_to_file.tif')
    def initialize(path, params = {})
      @path = path
      @label = params[:label]
      @file_attributes = params[:file_attributes]
      @relative_path = params[:relative_path]
      @provider_md5 = params[:provide_md5]
      @provider_sha1 = params[:provider_sha1]
    end

    # @return [String] DPG base filename, removing the extension and the '00','05', etc. placeholders
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/cy565rm7188_00_001.tif')
    #   puts source_file.dpg_basename # "cy565rm7188_001"
    def dpg_basename
      file_parts = File.basename(path, ext).split('_')
      file_parts.size == 3 ? "#{file_parts[0]}_#{file_parts[2]}" : filename_without_ext
    end

    # @return [String] DPG subfolder for the given filename, i.e. '00','05', etc.
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/cy565rm7188_00_001.tif')
    #   puts source_file.dpg_folder # "00"
    def dpg_folder
      file_parts = File.basename(path, ext).split('_')
      file_parts.size == 3 ? file_parts[1] : ''
    end

    # @return [String] base filename
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.filename # "path_to_file.tif"
    def filename
      File.basename(path)
    end

    # @return [String] base directory
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.dirname # "/input"
    def dirname
      File.dirname(path)
    end

    # @return [String] filename extension
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.ext # ".tif"
    def ext
      File.extname(path)
    end

    # @return [String] base filename without extension
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.filename # "path_to_file"
    def filename_without_ext
      File.basename(path, ext)
    end

    # @return [MiniExiftool] exif information stored as a hash and an object
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.exif # hash with exif information
    def exif
      check_for_file unless @exif
      begin
        @exif ||= MiniExiftool.new(@path, replace_invalid_chars: '?')
      rescue StandardError
        @exif = nil
      end
    end

    # Computes md5 checksum or returns cached value
    # @return [String] md5 checksum
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.md5 # 'XXX123XXX1243XX1243'
    def md5
      check_for_file unless @md5
      @md5 ||= Digest::MD5.file(path).hexdigest
    end

    # Computes sha1 checksum or return cached value
    # @return [String] sha1 checksum
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.sha1 # 'XXX123XXX1243XX1243'
    def sha1
      check_for_file unless @sha1
      @sha1 ||= Digest::SHA1.file(path).hexdigest
    end

    # Returns mimetype information for the current file based on file extension or exif data (if available)
    # @return [String] mime type
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.txt')
    #   puts source_file.mimetype # 'text/plain'
    def mimetype
      if @mimetype.nil? # if we haven't computed it yet once for this object, try and get the mimetype
        if !exif.nil? && !exif.mimetype.nil? # try and get the mimetype from the exif data if it exists
          @mimetype = exif.mimetype
        else # otherwise get it from the mime-types gem (using the file extension) assuming we can find, if not, return blank
          mimetype = MIME::Types.type_for(@path).first
          @mimetype = mimetype ? mimetype.content_type : ''
        end
      end
      @mimetype
    end

    # Returns mimetype information for the current file based on unix file system command or exif data (if available).
    # @return [String] mime type for supplied file
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.txt')
    #   puts source_file.file_mimetype # 'text/plain'
    def file_mimetype
      check_for_file unless @file_mimetype
      if @file_mimetype.nil? # if we haven't computed it yet once for this object, try and get the mimetype
        @file_mimetype = `file --mime-type "#{@path}"`.delete("\n").split(':')[1].strip # first try and get the mimetype from the unix file command
        @file_mimetype = exif.mimetype if !Assembly::TRUSTED_MIMETYPES.include?(@file_mimetype) && !exif.nil? && !exif.mimetype.nil? # if it's not a "trusted" mimetype and there is exif data; get the mimetype from the exif
      end
      @file_mimetype
    end

    # @note Uses shell call to "file", only expected to work on unix based systems
    # @return [String] encoding for supplied file
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.txt')
    #   puts source_file.encoding # 'us-ascii'
    def encoding
      check_for_file unless @encoding
      @encoding ||= `file --mime-encoding "#{@path}"`.delete("\n").split(':')[1].strip
    end

    # @return [Symbol] the type of object, could be :application (for PDF or Word, etc), :audio, :image, :message, :model, :multipart, :text or :video
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.object_type # :image
    def object_type
      lookup = MIME::Types[mimetype][0]
      lookup.nil? ? :other : lookup.media_type.to_sym
    end

    # @return [Boolean] if object is an image
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.image? # true
    def image?
      object_type == :image
    end

    # Examines the input image for validity.  Used to determine if image is a valid and useful image.
    # If image is not a jp2, also checks if it is jp2able?
    # @return [Boolean] true if image is valid, false if not.
    # @example
    #   source_img = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_img.valid_image? # true
    def valid_image?
      result = image? ? true : false
      result = jp2able? unless mimetype == 'image/jp2' # further checks if we are not already a jp2
      result
    end

    # @return [Boolean] true if image has a color profile, false if not.
    # @example
    #   source_img = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_img.has_color_profile? # true
    def has_color_profile?
      exif.nil? ? false : (!exif['profiledescription'].nil? || !exif['colorspace'].nil?) # check for existence of profile description
    end

    # Examines the input image for validity to create a jp2.  Same as valid_image? but also confirms the existence of a profile description and further restricts mimetypes.
    # It is used by the assembly robots to decide if a jp2 will be created and is also called before you create a jp2 using assembly-image.
    # @return [Boolean] true if image should have a jp2 created, false if not.
    # @example
    #   source_img = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_img.jp2able? # true
    def jp2able?
      result = false
      unless exif.nil?
        result = Assembly::VALID_IMAGE_MIMETYPES.include?(mimetype) # check for allowed image mimetypes that can be converted to jp2
      end
      result
    end

    # Returns file size information for the current file in bytes.
    # @return [Integer] file size in bytes
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.filesize # 1345
    def filesize
      check_for_file
      @filesize ||= File.size @path
    end

    # Determines if the file exists (and is not a directory)
    # @return [Boolean] file exists
    # @example
    #   source_file = Assembly::ObjectFile.new('/input/path_to_file.tif')
    #   puts source_file.file_exists? # true
    def file_exists?
      File.exist?(@path) && !File.directory?(@path)
    end

    private

    # private method to check for file existence before operating on it
    def check_for_file
      raise "input file #{path} does not exist" unless file_exists?
    end
  end
end
