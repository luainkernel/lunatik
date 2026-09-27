# cpuexporter

[cpuexporter](daemon.lua) will gather CPU usage statistics and expose using [OpenMetrics text format](https://github.com/prometheus/OpenMetrics/blob/main/specification/OpenMetrics.md#text-format) at the abstract UNIX socket `cpuexporter`, which leaves no file behind a stop.

## Usage

```shell
sudo make examples_install         	# installs examples
sudo lunatik spawn examples/cpuexporter/daemon # runs cpuexporter
sudo socat - ABSTRACT-CONNECT:cpuexporter <<<""
# TYPE cpu_usage_system gauge
cpu_usage_system{cpu="cpu1"} 0.0000000000000000 1764094519529162
cpu_usage_system{cpu="cpu0"} 0.0000000000000000 1764094519529162
# TYPE cpu_usage_idle gauge
cpu_usage_idle{cpu="cpu1"} 100.0000000000000000 1764094519529162
cpu_usage_idle{cpu="cpu0"} 100.0000000000000000 1764094519529162
...
```

