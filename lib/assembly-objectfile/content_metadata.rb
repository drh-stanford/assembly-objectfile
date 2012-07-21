require 'nokogiri'

module Assembly

  # This class generates content metadata for image files
  class ContentMetadata
    
      # Generates image content XML metadata for a repository object.
      # This method only produces content metadata for images
      # and does not depend on a specific folder structure.  Note that it is class level method.
      #
      # @param [Hash] params a hash containg parameters needed to produce content metadata
      #   :druid = required - a string of druid of the repository object's druid id without 'druid:' prefix
      #   :objects = required - an array of Assembly::ObjectFile objects containing the list of files to add to content metadata      
      #   :style = optional - a symbol containing the style of metadata to create, allowed values are
      #                 :simple_image (default), contentMetadata type="image", resource type="image"
      #                 :file, contentMetadata type="file", resource type="file"      
      #                 :simple_book, contentMetadata type="book", resource type="page"
      #                 :book_with_pdf, contentMetadata type="book", resource type="page", but each pdf will get it's own resource as resource type="file"
      #                 :book_as_image, contentMetadata type="book", resource type="image"
      #   :bundle = optional - a symbol containing the method of bundling files into resources, allowed values are
      #                 :default = all files get their own resources (default)
      #                 :filename = files with the same filename but different extensions get bundled together in a single resource
      #                 :dpg = files representing the same image but of different mimetype that use the SULAIR DPG filenaming standard (00 vs 05) get bundled together in a single resource
      #   :add_exif = optional - a boolean to indicate if exif data should be added (mimetype, filesize, image height/width, etc.) to each file, defaults to false and is not required if project goes through assembly
      #   :add_file_attributes = optional - a boolean to indicate if publish/preserve/shelve attributes should be added using defaults of supplied override by mime/type, defaults to false and is not required if project goes through assembly
      #   :file_attributes = optional - a hash of file attributes by mimetype to use instead of defaults, only used if add_file_attributes is also true, e.g. {'image/tif'=>{:preserve=>'yes',:shelve=>'no',:publish=>'no'},'application/pdf'=>{:preserve=>'yes',:shelve=>'yes',:publish=>'yes'}}
      #
      # Example:
      #    Assembly::Image.create_content_metadata(:druid=>'nx288wh8889',:style=>:simple_image,:objects=>object_files,:file_attributes=>false)
      def self.create_content_metadata(params={})

        druid=params[:druid]
        objects=params[:objects]

        raise "No objects and/or druid supplied" if druid.nil? || objects.nil? || objects.size == 0
        objects.each {|obj| raise "File #{obj.path} not found" unless obj.file_exists?}
        
        style=params[:style] || :simple_image
        bundle=params[:bundle] || :default
        add_exif=params[:add_exif] || false
        add_file_attributes=params[:add_file_attributes] || false
        file_attributes=params[:file_attributes] || {}

        content_type_descriptions={:file=>'file',:image=>'image',:book=>'book'}
        resource_type_descriptions={:file=>'file',:image=>'image',:book=>'page'}
        
        case style
          when :simple_image
            content_type_description = content_type_descriptions[:image]
            resource_type_description = resource_type_descriptions[:image]
          when :file
            content_type_description = content_type_descriptions[:file]
            resource_type_description = resource_type_descriptions[:file]           
          when :simple_book,:book_with_pdf
            content_type_description = content_type_descriptions[:book]
            resource_type_description = resource_type_descriptions[:book]
          when :book_as_image
            content_type_description = content_type_descriptions[:book]
            resource_type_description = resource_type_descriptions[:image]   
          else
            raise "Supplied style not valid"
        end
          
        sequence = 0
        file_sequence = 0
        
        # determine how many resources to create
        # setup an array if arrays, where the first array is the number of resources, and the second array is the object files containined in that resource
        case bundle
          when :default # one resource per object
            resources=objects.collect {|obj| [obj]}
          when :filename # one resource per distinct filename (excluding extension)
            # loop over distinct filenames, this determines how many resources we will have and
            # create one resource node per distinct filename, collecting the relevant objects with the distinct filename into that resource
            resources=[]
            distinct_filenames=objects.collect {|obj| obj.filename_without_ext}.uniq # find all the unique filenames in the set of objects, leaving off extensions and base paths
            distinct_filenames.each {|distinct_filename| resources << objects.collect {|obj| obj if obj.filename_without_ext == distinct_filename}.compact }
          when :dpg # group by DPG filename
            # loop over distinct dpg base names, this determines how many resources we will have and
            # create one resource node per distinct dpg base name, collecting the relevant objects with the distinct names into that resource
            resources=[]
            distinct_filenames=objects.collect {|obj| obj.dpg_basename}.uniq # find all the unique DPG filenames in the set of objects
            distinct_filenames.each {|distinct_filename| resources << objects.collect {|obj| obj if obj.dpg_basename == distinct_filename}.compact }
        end
        
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.contentMetadata(:objectId => "#{druid}",:type => content_type_description) {
            resources.each do |resource_files|
              sequence += 1
              resource_id = "#{druid}_#{sequence}"
              # start a new resource element
              
                xml.resource(:id => resource_id,:sequence => sequence,:type => resource_type_description) {
                xml.label "#{resource_type_description.capitalize} #{sequence}"

                  resource_files.each do |obj|
                  
                    mimetype = obj.mimetype
                    xml_file_params = {:id=> obj.content_metadata_path}
                  
                    if add_file_attributes
                      file_attributes_hash=file_attributes[mimetype] || Assembly::FILE_ATTRIBUTES[mimetype] || Assembly::FILE_ATTRIBUTES['default']
                      xml_file_params.merge!({
                        :preserve => file_attributes_hash[:preserve],
                        :publish  => file_attributes_hash[:publish],
                        :shelve   => file_attributes_hash[:shelve],
                      })
                    end
                    
                    # if we are doing book as image format and we encounter a resource with an object that is not a file, switch the resource type and label to "file"
                    if style=:book_as_image && !obj.image?
                      file_sequence += 1
                      xml.parent.attributes['type'].value=resource_type_descriptions[:file] 
                      xml.parent.xpath("label")[0].content = "#{resource_type_descriptions[:file].capitalize} #{file_sequence}"
                    end
                    
                    xml_file_params.merge!({:mimetype => mimetype,:size => obj.filesize}) if add_exif
                    xml.file(xml_file_params) {
                      if add_exif # add exif info if the user requested it
                        xml.checksum(obj.sha1, :type => 'sha1')
                        xml.checksum(obj.md5, :type => 'md5')                                
                        xml.imageData(:height => obj.exif.imageheight, :width => obj.exif.imagewidth) if obj.image? # add image data for an image
                      elsif obj.provider_md5 || obj.provider_sha1 # if we did not add exif info, see if there are user supplied checksums to add
                        xml.checksum(obj.provider_sha1, :type => 'sha1') if obj.provider_sha1
                        xml.checksum(obj.provider_md5, :type => 'md5') if obj.provider_md5                                                    
                      end #add_exif
                    }
                  end # end resource_files.each
              }
            end # resources.each
          }
        end
                
        return builder.to_xml

      end
      
  end
  
end