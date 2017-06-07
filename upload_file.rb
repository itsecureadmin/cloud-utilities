#!/usr/bin/env ruby

require 'rubygems'
require 'aws-sdk'
require 'yaml'

PART_SIZE=1024*1024*10

class File
  def each_part(part_size=PART_SIZE)
    yield read(part_size) until eof?
  end
end

(access,secret,bucket,localfile,prefix) = ARGV

s3 = Aws::S3::Client.new(
  region: 'us-east-1',
  credentials: Aws::Credentials.new(access,secret),
)

#
# map mime types
#
mime_types = {
  bz2: 'application/x-bzip2',
  pkg: 'application/x-newton-compatible-pkg',
  zip: 'application/zip',
}

#
# upload file from disk
#
begin

  #
  # strip any preceding path characteristics from the filename for key purposes
  #
  filebasename = File.basename(localfile)

  #
  # if a prefix is supplied, add it to the object key
  #
  if prefix
    key = prefix + "/" + filebasename
  else
    key = filebasename
  end

  File.open(localfile, 'rb') do |file|
    if file.size > PART_SIZE
      puts "File size over #{PART_SIZE} bytes, using multipart upload..."

      file_type = key.split(//).last(3).join
      mime_type = mime_types[:"#{file_type}"]

      if defined? mime_type
        input_opts = {
          bucket:       bucket,
          key:          key,
          content_type: mime_type,
        }
      else
        input_opts = {
          bucket:       bucket,
          key:          key,
        }
      end

      mpu_create_response = s3.create_multipart_upload(input_opts)

      total_parts = file.size.to_f / PART_SIZE
      current_part = 1

      file.each_part do |part|

        part_response = s3.upload_part({
          body:        part,
          bucket:      bucket,
          key:         key,
          part_number: current_part,
          upload_id:   mpu_create_response.upload_id,
        })

        percent_complete = (current_part.to_f / total_parts.to_f) * 100
        percent_complete = 100 if percent_complete > 100
        percent_complete = sprintf('%.2f', percent_complete.to_f)
        puts "percent complete: #{percent_complete}"
        current_part = current_part + 1

      end

      input_opts.delete_if {|key,value| key.to_s.eql?("content_type") }

      input_opts = input_opts.merge({
          :upload_id   => mpu_create_response.upload_id,
      })

      parts_resp = s3.list_parts(input_opts)

      input_opts = input_opts.merge(
          :multipart_upload => {
            :parts =>
              parts_resp.parts.map do |part|
              { :part_number => part.part_number,
                :etag        => part.etag }
              end
          }
        )

      mpu_complete_response = s3.complete_multipart_upload(input_opts)

    else

      file_type = key.split(//).last(3).join
      mime_type = mime_types[:"#{file_type}"]

      if defined? mime_type
        s3.put_object(
          bucket:       bucket,
          key:          key,
          body:         file,
          content_type: mime_type
        )
      else
        s3.put_object(
          bucket:       bucket,
          key:          key,
          body:         file
        )
      end

    end
  end

rescue Errno::ENOENT

  puts ""
  puts "File does not exist - please verify"
  puts ""
  exit 1

rescue Aws::S3::Errors::NoSuchBucket

  puts ""
  puts "That *bucket* does not exist."
  puts ""
  exit 1

rescue Aws::S3::Errors::NoSuchKey

  puts ""
  puts "That *file* does not exist."
  puts ""
  exit 1

rescue Aws::S3::Errors::ServiceError => se

  puts "Unknown problem."
  puts "#{se.class}"
  puts "#{se.message}"
  if mpu_create_response.upload_id
    resp = s3.abort_multipart_upload({
      bucket:    bucket,
      key:       key,
      upload_id: mpu_create_response.upload_id,
    })
  end
  exit 1

end
