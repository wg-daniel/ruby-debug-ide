module Debugger
  module DebugServer
    class << self

      class DebugForwardingProxy
        def initialize(internal_socket, external_socket)
          @external_socket = external_socket
          @internal_socket = internal_socket
          @external_messages = Queue.new
          @internal_messages = Queue.new
        end

        def start
          $stderr.puts "Start"
          start_logging_messages(@internal_socket, @internal_messages)
          start_logging_messages(@external_socket, @external_messages)

          start_redirecting_messages(@external_socket, @internal_messages)
          start_redirecting_messages(@internal_socket, @external_messages)
        end

        def start_logging_messages(socket, message_queue)
          DebugThread.start do
            begin
              loop do
                msg = socket.gets
                #$stderr.puts "external_socket Message1=#{msg}"
                message_queue << msg
              end
            rescue => bt
              $stderr.puts "Exception: #{bt}"
              $stderr.puts bt.backtrace.map { |l| "\t#{l}" }.join("\n")
            end
          end
        end

        def start_redirecting_messages(socket, message_queue)
          DebugThread.start do
            begin
              loop do
                msg = message_queue.pop
                #$stderr.puts "external_socket Message2=#{msg}"
                socket.puts msg
              end
            rescue => bt
              $stderr.puts "Exception2: #{bt}"
              $stderr.puts bt.backtrace.map { |l| "\t#{l}" }.join("\n")
            end
          end
        end
      end

      def start_debug_server(internal_port, external_port, host)

        @external_sockets =  Queue.new

        @external_server = TCPServer.new external_port
        print_server_greeting_msg($stderr, host, external_port, internal_port)
        @internal_server = TCPServer.new internal_port
        @dispatcher_socket = nil

        DebugThread.start do
          begin
            while (external_socket = @external_server.accept)
              $stderr.puts "external_socket #{external_socket.object_id}"
              @external_sockets << external_socket
            end
          rescue => bt
            $stderr.puts "Exception: #{bt}"
            $stderr.puts bt.backtrace.map { |l| "\t#{l}" }.join("\n")
          end
        end

        DebugThread.start do
          begin
            while (internal_socket = @internal_server.accept)
              if !@dispatcher_socket
                $stderr.puts "dispatcher found"
                @dispatcher_socket = @external_sockets.pop
              end

              pid = internal_socket.gets
              $stderr.puts "new internal connection with pid=#{pid}"
              @dispatcher_socket.puts pid
              external_socket = @external_sockets.pop
              $stderr.puts "dispatcher#{@dispatcher_socket.object_id} notified"
              $stderr.puts "internal_socket #{internal_socket.object_id}"
              proxy = DebugForwardingProxy.new(internal_socket, external_socket)
              proxy.start
            end
          rescue => bt
            $stderr.puts "Exception: #{bt}"
            $stderr.puts bt.backtrace.map { |l| "\t#{l}" }.join("\n")
          end
        end
      end

      def print_server_greeting_msg(stream, host, external_port, internal_port)
        base_gem_name = if defined?(JRUBY_VERSION) || RUBY_VERSION < '1.9.0'
                          'ruby-debug-base'
                        elsif RUBY_VERSION < '2.0.0'
                          'ruby-debug-base19x'
                        else
                          'debase'
                        end

        if host && external_port && internal_port
          listens_on = " listens on #{host}:#{external_port} internal port:#{internal_port}\n"
        else
          listens_on = "\n"
        end

        msg = "Debugger Server (ruby-debug-ide #{IDE_VERSION}, #{base_gem_name} #{VERSION})" + listens_on

        stream.printf msg
      end
    end
  end
end