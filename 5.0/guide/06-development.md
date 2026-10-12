# Development

## Testing

Install and run the test suites:

```sh
sudo make install
sudo lunatik test           # run all suites
sudo lunatik test thread    # run a specific suite
```

`lunatik test` reloads the modules before the run and unloads them
afterwards, so each invocation exercises the currently-installed kernel
code. Both stop every running script, so do not run the suites on a machine
whose scripts must stay up. See [tests/README.md](../../tests/README.md) for the full list of suites
and individual tests.

## Contributing

Conventions for contributors, and for AI coding assistants working on this repository, are in
[AGENTS.md](../../AGENTS.md): build and test loop, execution contexts, object model, code style, and commit
discipline. Design notes for work in progress live under [doc/design](../design); what is being
worked on, and how far along it is, lives in the
[project boards](https://github.com/orgs/luainkernel/projects).


