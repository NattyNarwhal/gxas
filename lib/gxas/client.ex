defmodule Gxas.Client do
  require Logger
  use GenServer

  def start_link(socket, opts \\ []) do
    GenServer.start_link(__MODULE__, socket, opts)
  end

  def init(socket) do
    Logger.info("[TCP] Initialized")
    {:ok, {remote_ip, remote_port}} = :inet.peername(socket)
    state = %{
      socket: socket,
      # For debugging
      socket_string: "#{:inet.ntoa(remote_ip)}:#{remote_port}",
      state: :verb,
      client_headers: [],
      first_relay_sent: false
    }
    {:ok, state}
  end

  defp send_app_list_cooked(socket) do
    {:ok, binary} = File.read("apps2.bin")
    content_length = byte_size(binary)
    headers = [
      "HTTP/1.0 200 OK",
      "Connection: close",
      "Accept-Ranges: none",
      "Content-Length: #{content_length}",
      # It's not really XML
      "Content-Type: text/xml",
    ]
    # two newlines to terminate
    headers_cooked = Enum.join(headers, "\r\n") <> "\r\n\r\n"
    # XXX: We have no idea what the format is so we send the same blob the
    # Russian server does for now
    :gen_tcp.send(socket, headers_cooked <> binary)
  end

  defp send_first_relay(socket, first_packet) do
    # We need to send the first packet we receive relaying as if it was HTTP
    headers = [
      "HTTP/1.0 200 Connection Established",
      "Connection: close",
      "Accept-Ranges: none",
    ]
    headers_cooked = Enum.join(headers, "\r\n") <> "\r\n\r\n"
    :gen_tcp.send(socket, headers_cooked <> first_packet)
  end

  defp start_relay() do
    #:gen_tcp.connect({192, 168, 2, 31}, 5900, [:binary, packet: :raw, active: true])
    :gen_tcp.connect({127, 0, 0, 1}, 5969, [:binary, packet: :raw, active: true])
  end

  def handle_info({:tcp_error, socket, error}, state) do
    socket_string = cond do
      socket == state.socket -> "socket " <> state.socket_string
      socket == state.relay_socket -> "relayed socket " <> state.relay_socket_string
    end
    Logger.info("[TCP] Exiting from socket error (#{error}) on #{socket_string}, state #{state.state}")
    Process.exit(self(), :normal)
  end

  def handle_info({:tcp_closed, socket}, state) do
    socket_string = cond do
      socket == state.socket -> "socket " <> state.socket_string
      socket == state.relay_socket -> "relayed socket " <> state.relay_socket_string
    end
    Logger.info("[TCP] Exiting from socket close on #{socket_string} state #{state.state}")
    Process.exit(self(), :normal)
  end

  # APPCONFIG
  def handle_info({:tcp, socket, newline}, %{state: :config_headers} = state) when newline in ["\r\n", "\n"] do
    Logger.info("[CFG] No more config headers")
    new_state = state
                |> Map.put(:state, :config_done)
    # The phone sends more bursts of info in a binary format after we send this
    :inet.setopts(socket, packet: :raw)
    send_app_list_cooked(socket)
    {:noreply, new_state}
  end

  def handle_info({:tcp, _socket, header}, %{state: :config_headers} = state) do
    Logger.info("[CFG] Adding initial config header #{header}")
    new_headers = [header | state.client_headers]
    new_state = state
                |> Map.put(:client_headers, new_headers)
    {:noreply, new_state}
  end

  def handle_info({:tcp, _socket, "APPCONFIG" <> args}, %{state: :verb} = state) do
    Logger.info("[CFG] Initial APPCONFIG request")
    [_path, _http_1_0] = String.split(args)
    new_state = state
                |> Map.put(:state, :config_headers)
    {:noreply, new_state}
  end

  # APPCONNECT
  def handle_info({:tcp, socket, newline}, %{state: :connect_headers} = state) when newline in ["\r\n", "\n"] do
    Logger.info("[CON] No more connect headers, switching to relay")
    {:ok, relay_socket} = start_relay()
    {:ok, {remote_ip, remote_port}} = :inet.peername(relay_socket)
    # We no longer care about HTTP line discipline
    :inet.setopts(socket, packet: :raw)
    new_state = state
                |> Map.put(:state, :relay)
                |> Map.put(:relay_socket, relay_socket)
                |> Map.put(:relay_socket_string, "#{:inet.ntoa(remote_ip)}:#{remote_port}")
    {:noreply, new_state}
  end

  def handle_info({:tcp, _socket, header}, %{state: :connect_headers} = state) do
    Logger.info("[CON] Adding initial connect header #{header}")
    new_headers = [header | state.client_headers]
    new_state = state
                |> Map.put(:client_headers, new_headers)
    {:noreply, new_state}
  end

  def handle_info({:tcp, _socket, "APPCONNECT " <> args}, %{state: :verb} = state) do
    Logger.info("[CON] Initial APPCONNECT request")
    # {VNC address on host, HTTP version}
    [_vnc_addr, _http_1_0] = String.split(args)
    new_state = state
                |> Map.put(:state, :connect_headers)
    {:noreply, new_state}
  end

  def handle_info({:tcp, socket, data}, %{state: :relay} = state) do
    hex_data = Base.encode16(data)
    # XXX: This could probably be a pattern match in the function decl
    new_state = cond do
      socket == state.socket ->
        Logger.info("[RLY] Got relay data for client #{hex_data}")
        :gen_tcp.send(state.relay_socket, data)
        state
      socket == state.relay_socket && state.first_relay_sent == false ->
        Logger.info("[RLY] Got relay data for VNC (first) #{hex_data}")
        send_first_relay(state.socket, data)
        Map.put(state, :first_relay_sent, true)
      socket == state.relay_socket ->
        Logger.info("[RLY] Got relay data for VNC #{hex_data}")
        :gen_tcp.send(state.socket, data)
        state
    end
    {:noreply, new_state}
  end

  # Fallback
  def handle_info({:tcp, socket, data}, %{state: :config_done} = state) do
    hex_data = Base.encode16(data)
    Logger.info("[TCP] Unknown data #{hex_data} with state #{state.state}")
    #:gen_tcp.send(socket, "\x00\x00\x00\x00\x00\x00\x00\x0b\x00\x00\x00\x00\x00\x00\x00\x07\x00\x00\x00\x00")
    {:noreply, state}
  end

  def handle_info({:tcp, _socket, data}, state) do
    hex_data = Base.encode16(data)
    Logger.info("[TCP] Unknown data #{hex_data} with state #{state.state}")
    {:noreply, state}
  end
end
