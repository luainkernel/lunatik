import concat from table
import ntoh16 from require"linux"

DEBUG = false
dbg = (...) -> print ... if DEBUG


Object = {
  __name: "Object"
  new: (obj) =>
    cls = @ ~= obj and @ or nil
    setmetatable obj, {
      __index: (k) =>
        if cls
          if getter = cls["_get_#{k}"]
            @k = getter @
            dbg "#{@__name} #{k}: #{@k}"
            @k
          else
            cls[k]
      __call: (...) => obj\new ...
    }
}
Object.new Object, Object
subclass = Object.new


Packet = subclass Object, {
  __name: "Packet"
  new: (obj) =>
    assert obj.skb, "I need a skb to parse"
    obj.off or= 0
    Object.new @, obj

  nibble: (offset, half = 0) =>
    b = @skb\getbyte @off+offset
    half == 0 and b >> 4 or b & 0xf

  byte: (offset) =>
    if DEBUG
      ok, ret = pcall @skb.getbyte, @skb, @off+offset
      ret if ok else print"ERR: byte, #{ret}, #{@off}, #{offset}, #{#@skb}"
    else
      @skb\getbyte @off+offset

  short: (offset) =>
    if DEBUG
      ok, ret = pcall @skb.getuint16, @skb, @off+offset
      ntoh16(ret) if ok else print"ERR: short, #{ret}, #{@off}, #{offset}, #{#@skb}"
    else
      ntoh16 @skb\getuint16 @off+offset

  str: (offset=0, length=#@skb-@off) =>
    if DEBUG
      ok, ret = pcall @skb.getstring, @skb, @off+offset, length
      ret if ok else print"ERR: str, #{ret}, #{@off}, #{offset}, #{length}, #{#@skb}"
    else
      @skb\getstring @off+offset, length

  is_empty: => @off == #@skb

  _get_data: => skb: @skb, off: @off + @data_off
}


IP = subclass Packet, {
  __name: "IP"
  _get_version: => @nibble 0
}


IP4 = subclass IP, {
  __name: "IP4"

  get_ip_at: (off) => concat [ "%d"\format(@byte i) for i = off, off+3 ], "."

  _get_length: => @short 2

  _get_src: => @get_ip_at 12

  _get_dst: => @get_ip_at 16

  _get_data_off: => 4 * @nibble 0, 1
}


IP6 = subclass IP, {
  __name: "IP6"
  
  get_ip_at: (off) => concat [ "%x"\format(@short i) for i = off, off+14, 2 ], ":"

  _get_length: => @data_off + @short 4

  _get_src: => @get_ip_at 8

  _get_dst: => @get_ip_at 24

  _get_data_off: => 40
}


auto_ip = =>
  version = IP(skb: @).version
  _ip = version == 4 and IP4 or version == 6 and IP6
  _ip skb: @


TCP = subclass Packet, {
  __name: "TCP"
  
  _get_data_off: => 4 * @nibble 12
}


TLS = subclass Packet, {
  __name: "TLS"
  
  _get_type: => @byte 0
  
  _get_version: => "#{@byte 1}.#{@byte 2}"
  
  _get_length: => @short 3
  
  _get_data_off: => 5

  types: {
    handshake: 0x16
  }
}


TLSExtension = subclass Packet, {
  __name: "TLSExtension"
  
  _get_type: => @short 0
  
  _get_length: => 4 + @short 2

  types: {
    server_name: 0x00
  }
}


TLS_extensions = setmetatable {
  [0x00]: subclass TLSExtension, {
    __name: "ServerNameIndication"
    
    _get_type_str: => "server name"
  
    _get_server_name: => @str 9, @short 7
  }
}, __index: (k) => subclass TLSExtension, {
  __name: "UnknownTlsExtension"
  
  _get_type_str: => "unknown"
}


TLSHandshake = subclass Packet, {
  __name: "TLSHandshake"
  
  _get_type: => @byte 0
  
  _get_length: => @byte(1) << 16 | @short 2
  
  _get_client_version: => "#{@byte 4}.#{@byte 5}"
  
  _get_client_random: => @str 6, 32
  
  _get_session_id_length: => @byte 38
  
  _get_session_id: => @str 39, @session_id_length
  
  _get_ciphers_offset: => 39 + @session_id_length
  
  _get_ciphers_length: => @short @ciphers_offset
  
  _get_ciphers: => [ @short(@ciphers_offset + 2 + i) for i = 0, @ciphers_length-2, 2 ]
  
  _get_compressions_offset: => @ciphers_offset + 2 + @ciphers_length
  
  _get_compressions_length: => @byte @compressions_offset
  
  _get_compressions: => [ @byte(@compressions_offset + 1 + i) for i = 0, @compressions_length - 1 ]
  
  _get_extensions_offset: => @compressions_offset + 1 + @compressions_length
  
  _get_extensions: =>
    extensions = {}
    offset = @extensions_offset + 2
    max_offset = offset + @short @extensions_offset
    while offset < max_offset
      extension = TLS_extensions[@short offset] skb: @skb, off: @off + offset
      extensions[#extensions+1] = extension
      offset += extension.length
    extensions

  types: {
    hello: 0x01
  }
}


{
  :DEBUG, :dbg,
  :Object, :subclass,
  :Packet, :IP, :IP4, :IP6, :auto_ip,
  :TCP,
  :TLS, :TLSExtension, :TLSHandshake, :TLS_extensions
}

