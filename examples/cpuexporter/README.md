# cpuexporter

[cpuexporter](daemon.lua) will gather CPU usage statistics and expose them in the [Prometheus text exposition format](https://prometheus.io/docs/instrumenting/exposition_formats/#text-based-format) (version 0.0.4) at the abstract UNIX socket `cpuexporter`, which leaves no file behind a stop.
A client that sends anything but an HTTP request gets the metrics alone; a `GET /metrics` gets them as an HTTP response.

## Usage

```shell
sudo make install                 	# installs Lunatik and the examples
sudo lunatik spawn examples/cpuexporter/daemon # runs cpuexporter
sudo socat - ABSTRACT-CONNECT:cpuexporter <<<""
# TYPE cpu_usage_system gauge
cpu_usage_system{cpu="cpu1"} 0.00 1764094519529
cpu_usage_system{cpu="cpu0"} 0.00 1764094519529
# TYPE cpu_usage_idle gauge
cpu_usage_idle{cpu="cpu1"} 100.00 1764094519529
cpu_usage_idle{cpu="cpu0"} 100.00 1764094519529
...
```

For a scraper, bridge a TCP port to the socket and ask for `/metrics`:

```shell
socat TCP-LISTEN:9100,bind=127.0.0.1,fork ABSTRACT-CONNECT:cpuexporter &
curl http://127.0.0.1:9100/metrics
kill %1
sudo lunatik stop examples/cpuexporter/daemon # stops cpuexporter
```

