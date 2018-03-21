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
                message_queue << msg
              end
            rescue => bt
              print_debug(bt.message)
            end
          end
        end

        def start_redirecting_messages(socket, message_queue)
          DebugThread.start do
            begin
              loop do
                msg = message_queue.pop
                socket.puts msg
              end
            rescue => bt
              print_debug(bt.message)
            end
          end
        end
      end

      def read_pid_from_file(path)
        pid = nil
        f = File.open(path, "r")
        f.each_line do |line|
          line.scan(/\d+/) do |x|
            pid = x
          end
        end
        f.close
        pid
      end

      def write_pid_to_file(pid, path)
        File.open(path, 'w') { |file| file.write(pid) }
      end

      def check_server(port, path)
        begin
          port = read_pid_from_file path

          ping_session = TCPSocket.new('127.0.0.1', port)
          ping_session.puts -1

          return port
        rescue
          return nil
        end
      end

      def start_debug_server(external_port, host)
        pid_file_path = File.expand_path(File.dirname(__FILE__) + '/server.pid')
        created_port = check_server(external_port, pid_file_path)
        return created_port if created_port
        internal_port = Debugger.find_free_port host

        write_pid_to_file(internal_port, pid_file_path)

        @external_sockets =  Queue.new

        @external_server = TCPServer.new external_port
        print_server_greeting_msg($stderr, host, external_port, internal_port)
        @internal_server = TCPServer.new internal_port
        @dispatcher_socket = nil

        DebugThread.start do
          begin
            while (external_socket = @external_server.accept)
              @external_sockets << external_socket
            end
          rescue => bt
            print_debug(bt.message)
          end
        end

        DebugThread.start do
          begin
            while (internal_socket = @internal_server.accept)
              unless @dispatcher_socket
                @dispatcher_socket = @external_sockets.pop
              end

              pid = internal_socket.gets.to_i
              next if pid < 0

              @dispatcher_socket.puts pid
              external_socket = @external_sockets.pop
              proxy = DebugForwardingProxy.new(internal_socket, external_socket)
              proxy.start
            end
          rescue => bt
            print_debug(bt.message)
          end
        end

        internal_port
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