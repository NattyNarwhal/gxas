defmodule Gxas.Server do
  require Logger
  use Task

  # based on http://www.robgolding.com/blog/2019/05/21/tcp-genserver-elixir/
  def start_link(args) do
    Logger.info("[SUP] Starting link for GXAS server")
    Task.start_link(__MODULE__, :accept, [args])
  end

  def accept(args) do
    # When we're done the HTTP handshaking, we should do
    # :inet:setoptions(socket, packet: :raw)
    # so we no longer need receiving line packets
    # see http://erlang.org/doc/man/inet.html#setopts-2 (PacketType)
    {:ok, listener} = :gen_tcp.listen(
      args.port,
      [:binary, packet: :line, active: :true, reuseaddr: true]
    )
    Logger.info("[TCP] accepting on port #{args.port}")
    listen(listener)
  end

  def listen(listener) do
    {:ok, socket} = :gen_tcp.accept(listener)
    {:ok, {remote_ip, remote_port}} = :inet.peername(socket)
    Logger.info("[TCP] accepted socket for #{:inet.ntoa(remote_ip)}:#{remote_port}")
    {:ok, pid} = DynamicSupervisor.start_child(
      Gxas.ClientSupervisor,
      {Gxas.Client, socket}
    )
    :gen_tcp.controlling_process(socket, pid)
    listen(listener)
  end
end
