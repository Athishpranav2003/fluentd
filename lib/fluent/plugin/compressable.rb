#
# Fluentd
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

require 'stringio'
require 'zlib'
require 'zstd-ruby'

module Fluent
  module Plugin
    module Compressable
      def compress(data, type: :gzip, **kwargs)
        output_io = kwargs[:output_io]
        writer = nil
        io = output_io || StringIO.new
        if type == :gzip
          writer = Zlib::GzipWriter.new(io)
        elsif type == :zstd
          writer = Zstd::StreamWriter.new(io)
        else
          raise ArgumentError, "Unknown compression type: #{type}"
        end
        writer.write(data)
        writer.finish
        output_io || io.string
      end

      # compressed_data is String like `compress(data1) + compress(data2) + ... + compress(dataN)`
      # https://www.ruby-forum.com/topic/971591#979503
      def decompress(compressed_data = nil, output_io: nil, input_io: nil, type: :gzip)
        case
        when input_io && output_io
          io_decompress(input_io, output_io, type)
        when input_io
          output_io = StringIO.new
          io = io_decompress(input_io, output_io, type)
          io.string
        when compressed_data.nil? || compressed_data.empty?
          # check compressed_data(String) is 0 length
          compressed_data
        when output_io
          # execute after checking compressed_data is empty or not
          io = StringIO.new(compressed_data)
          io_decompress(io, output_io, type)
        else
          string_decompress(compressed_data, type)
        end
      end

      private

      def string_decompress(compressed_data, type = :gzip)
        io = StringIO.new(compressed_data)

        out = ''
        loop do
          if type == :gzip
            reader = Zlib::GzipReader.new(io)
            out << reader.read
            unused = reader.unused
            reader.finish

            unless unused.nil?
              adjust = unused.length
              io.pos -= adjust
            end
          elsif type == :zstd
            reader = Zstd::StreamReader.new(io)
            # Zstd::StreamReader needs to specify the size of the buffer
            out << reader.read(1024)
            # Zstd::StreamReader doesn't provide unused data, so we have to manually adjust the position
          else
            raise ArgumentError, "Unknown compression type: #{type}"
          end
          break if io.eof?
        end

        out
      end

      def io_decompress(input, output, type = :gzip)
        loop do
          reader = nil
          if type == :gzip
            reader = Zlib::GzipReader.new(input)
            v = reader.read
            output.write(v)
            unused = reader.unused
            reader.finish
            unless unused.nil?
              adjust = unused.length
              input.pos -= adjust
            end
          elsif type == :zstd
            reader = Zstd::StreamReader.new(input)
            # Zstd::StreamReader needs to specify the size of the buffer
            v = reader.read(1024)
            output.write(v)
            # Zstd::StreamReader doesn't provide unused data, so we have to manually adjust the position
          else
            raise ArgumentError, "Unknown compression type: #{type}"
          end
          break if input.eof?
        end

        output
      end
    end
  end
end
