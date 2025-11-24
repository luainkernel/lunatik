# DNS Rewrite Example

This example demonstrates how to intercept DNS queries and respond directly with a custom IP address. It uses Lunatik's netfilter hooks to handle DNS packets at the kernel level without letting them reach the internet.

## What It Does

The `dnsrewrite` example intercepts DNS queries for `test.internal` and responds directly with `127.0.0.1` (localhost), preventing the query from being sent to external DNS servers.

## How It Works

1. **Netfilter Hooks**: Registers hooks at both `LOCAL_OUT` and `PRE_ROUTING` points to intercept DNS query packets
2. **Packet Filtering**: Only processes UDP packets destined for port 53 (DNS)
3. **Domain Matching**: Parses the DNS question section to identify queries for `test.internal`
4. **Direct Response**: Builds a complete DNS response packet and sends it back to the querying application, preventing the query from reaching the internet

## Files

- `common.lua` - Core DNS packet parsing and response building logic
- `nf_dnsrewrite.lua` - Netfilter hook implementation

## Installation

From the main Lunatik directory:

```bash
sudo make examples_install
```

## Usage

Load the netfilter hook (note: must use `false` parameter for atomic/non-sleepable runtime):

```bash
sudo lunatik run examples/dnsrewrite/nf_dnsrewrite false
```

The `false` parameter is required because netfilter hooks run in atomic context and cannot sleep. The hook will remain active and intercept DNS queries until you unload it.

## Testing

Query for `test.internal`:

```bash
# Using dig
dig test.internal

# Using nslookup
nslookup test.internal
```

The DNS query will resolve to `127.0.0.1` without ever leaving your machine.

You can verify the interception with a packet capture:

```bash
# In another terminal, capture DNS traffic
sudo tcpdump -i any -n port 53
```

You'll see the query and response packets, but no packets will be sent to external DNS servers.

## Stopping

To stop the DNS rewriting:

```bash
sudo lunatik stop examples/dnsrewrite/nf_dnsrewrite
```

## Customization

To rewrite a different domain or use a different IP address, edit `common.lua`:

```lua
-- Change the target domain (line 11)
local target_dns = string.pack("s1s1", "your", "domain")

-- Change the target IP address (line 14)
local target_ip = 0x7F000001  -- Change to your desired IP in hex
```

For example, to use `192.168.1.100`:
```lua
local target_ip = 0xC0A80164  -- 192.168.1.100 in hex
```

## Technical Details

### DNS Packet Structure

The code intercepts UDP/IP packets containing DNS queries and transforms them into responses:
- Ethernet header (14 bytes)
- IP header (variable length, calculated from IHL field)
- UDP header (8 bytes)
- DNS header (12 bytes)
- Question section (variable length, domain name + type + class)
- Answer section (16 bytes, A record with IP address)

### Domain Name Encoding

DNS uses length-prefixed labels. For example, `test.internal` is encoded as:
```
\x04test\x08internal\x00
```

The `string.pack("s1s1", "test", "internal")` function creates this encoding.

### IP Address Format

IP addresses are stored in network byte order (big-endian). The example uses:
- `127.0.0.1` = `0x7F000001` in hexadecimal

### Hook Points

The hooks are registered at two points with priority `MANGLE + 1`:
- **LOCAL_OUT**: Intercepts packets originating from the local machine before they are routed
- **PRE_ROUTING**: Intercepts packets entering the machine before routing decisions are made

This dual-hook approach ensures DNS queries are intercepted whether they come from local applications or are forwarded through the machine.

### How the Response Works

When a matching DNS query is detected:
1. The IP source and destination addresses are swapped
2. The UDP source and destination ports are swapped
3. DNS flags are set to indicate a response (QR=1, AA=1, RA=1)
4. Answer count is set to 1, authority and additional counts to 0
5. An A record answer is added with the target IP address
6. UDP and IP checksums are recalculated
7. The packet is accepted and delivered back to the querying application
8. The original query never reaches external DNS servers

### Non-Matching Domains

DNS queries for domains that don't match `test.internal` are allowed to proceed normally to external DNS servers. 

