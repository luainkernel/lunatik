# Lunatik Tests

Integration tests for lunatik kernel modules. Output follows
[KTAP](https://docs.kernel.org/dev-tools/ktap.html) format.

## Requirements

- Lunatik modules loaded: `sudo lunatik load`
- Lua scripts installed: `sudo make tests_install`
- Root privileges

## Running

All suites:

```
sudo bash tests/run.sh
```

