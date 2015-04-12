#!/usr/bin/env ruby

UDP_PORT=9998
TCP_PORT=9999
BROADCAST_IP='255.255.255.255'
LOOP_DELAY=10 # seconds sleep before sending the next boraodcast
EXPIRE_TIME=60 # seconds after a node is expired 

=begin
Copyright (C) 2015 Thomas Volk

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Lesser General Public License for more details.
 
You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.
=end

require 'socket'
require 'thread'

class Broadcast
  attr_accessor :port, :ip
  
  def initialize(ip, port)
    @ip = ip
    @port = port
  end
  
  def run
    sock = UDPSocket.new
    sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
    sock.bind(@ip, nil) 
    sock.send('HELLO', 0, "<broadcast>", @port)
    sock.close
  end
end 

class Server
  attr_accessor :port, :eventQueue
  
  def initialize(eventQueue, port)
    @eventQueue = eventQueue    
    @port = port
  end
  
  def run
    sock = UDPSocket.new
    sock.bind('', @port)
    while true
      msg, addr = sock.recvfrom(1024)
      if msg == 'HELLO'
        ip = addr[3]
        now = Time.now
        @eventQueue.push({ ip: ip, date: now, expired: now + EXPIRE_TIME })
      end   
    end
  end
end

class NodeCache
  attr_accessor :nodes
  
  def initialize
    @nodes = {}
  end
  
  def update(node)
    ip = node[:ip]
    if not @nodes[ip]
      puts "add new node %s" % node
    end
    @nodes[ip] = node
  end
  
  def cleanup
    now = Time.now
    @nodes = @nodes.select { |ip, conf|
      confirmed = now < conf[:expired]
      if not confirmed
        puts "remove node %s" % conf
      end
      confirmed
    }
  end
end

eventQueue = Queue.new
nodeCache = NodeCache.new
server = Server.new(eventQueue, UDP_PORT)
broadcast = Broadcast.new(BROADCAST_IP, UDP_PORT)

serverThread = Thread.new {
  server.run 
}

eventLoopThread = Thread.new { 
  loop do
    broadcast.run
    while (event = eventQueue.pop(true) rescue nil) do
      if event
        nodeCache.update(event)
      end
    end
    nodeCache.cleanup
    sleep LOOP_DELAY
  end
}

server = TCPServer.new TCP_PORT
loop do
  Thread.start(server.accept) do |client|
    client.puts nodeCache.nodes.collect { |ip, conf| }.join('\n')
    client.close
  end
end

serverThread.join
eventLoopThread.join
